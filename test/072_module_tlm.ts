import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id, constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

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
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
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

    tlmModule = (await deployContract(ownerAcc, TLMModuleArtifact, [cauldron.address, tlm.address])) as TLMModule
    await ladle.grantRoles([id('setModule(address,bool)')], owner)

    await ladle.ladle.setModule(tlmModule.address, true)
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

    it('sells fyToken in the TLM Module', async () => {
      // Load the TLM Module
      await ladle.pour(vaultId, tlmModule.address, WAD, WAD)

      const tlmSellSelector = id('tlmSell(address,bytes)')
      const tlmSellData = ethers.utils.defaultAbiCoder.encode(
        ['bytes6', 'address', 'uint256'],
        [seriesId, owner, WAD]
      )
      const moduleData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'bytes4', 'bytes'],
        [tlmModule.address, tlmSellSelector, tlmSellData]
      )

      expect(await ladle.ladle.batch([19], [moduleData]))
        .to.emit(base, 'Transfer')
        .withArgs(zeroAddress, owner, WAD)
    })
  })
})
