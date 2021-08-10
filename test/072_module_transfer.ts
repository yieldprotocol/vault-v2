import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id, constants } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants

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

describe('Ladle - module transfer', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let user1: string
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
    user1 = await signers[1].getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const wrongAssetId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
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

    // ==== Set Mock Module ====
    await ladle.grantRoles([id('setModule(address,bool)')], owner)
    await ladle.setModule(user1, true)
  })

  it('transferring to unregistered modules reverts', async () => {
    await expect(ladle.transferToModule(baseId, owner, WAD)).to.be.revertedWith('Unregistered module')
  })

  it('transferring unknown assets reverts', async () => {
    await expect(ladle.transferToModule(wrongAssetId, user1, WAD)).to.be.revertedWith('Unknown asset')
  })

  it('transfers to a module', async () => {
    await base.approve(ladle.address, WAD)
    await expect(ladle.transferToModule(baseId, user1, WAD))
      .to.emit(base, 'Transfer')
      .withArgs(owner, user1, WAD)
    expect(await base.balanceOf(user1)).to.equal(WAD)
  })
})
