import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id, constants } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants
import { ETH } from '../src/constants'

import TLMMockArtifact from '../artifacts/contracts/mocks/TLMMock.sol/TLMMock.json'
import TLMModuleArtifact from '../artifacts/contracts/modules/TLMModule.sol/TLMModule.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { TLMModule } from '../typechain/TLMModule'

import { ERC20Mock } from '../typechain/ERC20Mock'
import { TLMMock } from '../typechain/TLMMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - module', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let cauldron: Cauldron
  let ladle: LadleWrapper
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ilkJoin: Join
  let gemJoin: string
  let fyToken: FYToken
  let tlm: TLMMock
  let tlmModule: TLMModule
  let makerIlk: string
  let vaultId: string

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const zeroAddress = '0x' + '0'.repeat(40)

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    ilkJoin = env.joins.get(ilkId) as Join
    fyToken = env.series.get(seriesId) as FYToken

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    // ==== Set TLM and TLM Module ====
    tlm = (await deployContract(ownerAcc, TLMMockArtifact, [base.address, fyToken.address])) as TLMMock
    makerIlk = await tlm.FYDAI()
    gemJoin = (await tlm.ilks(makerIlk)).gemJoin

    tlmModule = (await deployContract(ownerAcc, TLMModuleArtifact, [
      cauldron.address,
      zeroAddress,
      tlm.address,
    ])) as TLMModule
    await ladle.grantRoles([id(ladle.ladle.interface, 'addModule(address,bool)')], owner)

    await ladle.addModule(tlmModule.address, true)
  })

  it('registers a series for sale in the TLM Module', async () => {
    await expect(tlmModule.register(seriesId, makerIlk))
      .to.emit(tlmModule, 'SeriesRegistered')
      .withArgs(seriesId, makerIlk)
    expect(await tlmModule.seriesToIlk(seriesId)).to.equal(makerIlk)
  })

  describe('with a registered series', async () => {
    beforeEach(async () => {
      await tlmModule.register(seriesId, makerIlk)
    })

    it('approves the TLM Module to take fyToken from the Ladle', async () => {
      await expect(ladle.tlmApprove(tlmModule.address, seriesId))
        .to.emit(fyToken, 'Approval')
        .withArgs(ladle.address, gemJoin, MAX256)
      expect(await fyToken.allowance(ladle.address, gemJoin)).to.equal(MAX256)
    })

    describe('with Ladle approval', async () => {
      beforeEach(async () => {
        await ladle.tlmApprove(tlmModule.address, seriesId)
      })

      it('sells fyToken in the TLM Module', async () => {
        expect(
          await ladle.batch([
            ladle.pourAction(vaultId, ladle.address, WAD, WAD),
            ladle.tlmSellAction(tlmModule.address, seriesId, owner, WAD),
          ])
        )
          .to.emit(base, 'Transfer')
          .withArgs(zeroAddress, owner, WAD)
      })
    })
  })
})
