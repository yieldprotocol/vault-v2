import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id, constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

import TransferModuleArtifact from '../artifacts/contracts/modules/TransferModule.sol/TransferModule.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { TransferModule } from '../typechain/TransferModule'

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
  let ilk: ERC20Mock
  let ilkJoin: Join
  let transferModule: TransferModule

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId, otherIlkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    ilk = env.assets.get(ilkId) as ERC20Mock

    ilkJoin = env.joins.get(ilkId) as Join

    // ==== Set transfer module ====
    transferModule = (await deployContract(ownerAcc, TransferModuleArtifact, [])) as TransferModule
    await ladle.grantRoles([id('setModule(address,bool)')], owner)

    await ladle.setModule(transferModule.address, true)

    await transferModule.grantRoles([id('transferFrom(address,bytes)')], ladle.address)
  })

  it('transfers token from src to dst', async () => {
    await ilk.mint(owner, WAD)
    await ilk.approve(transferModule.address, WAD)
    const transferFromSelector = id('transferFrom(address,bytes)')
    const transferFromData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'address', 'uint256'],
      [ilk.address, ilkJoin.address, WAD]
    )
    const moduleData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'bytes4', 'bytes'],
      [transferModule.address, transferFromSelector, transferFromData]
    )
    expect(await ladle.ladle.batch([19], [moduleData]))
      .to.emit(ilk, 'Transfer')
      .withArgs(owner, ilkJoin.address, WAD)
  })
})
