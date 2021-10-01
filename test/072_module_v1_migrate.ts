import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id, constants } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants
import { ETH, DAI } from '../src/constants'

import V1FYDaiMockArtifact from '../artifacts/contracts/mocks/v1/V1FYDaiMock.sol/V1FYDaiMock.json'
import V1PoolMockArtifact from '../artifacts/contracts/mocks/v1/V1PoolMock.sol/V1PoolMock.json'
import BurnModuleArtifact from '../artifacts/contracts/modules/BurnV1LiquidityModule.sol/BurnV1LiquidityModule.json'

import { Cauldron } from '../typechain/Cauldron'
import { BurnV1LiquidityModule } from '../typechain/BurnV1LiquidityModule'

import { ERC20Mock } from '../typechain/ERC20Mock'
import { DAIMock } from '../typechain/DAIMock'
import { V1FYDaiMock } from '../typechain/V1FYDaiMock'
import { V1PoolMock } from '../typechain/V1PoolMock'

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
  let fyDaiSep: V1FYDaiMock
  let fyDaiDec: V1FYDaiMock
  let v1PoolSep: V1PoolMock
  let v1PoolDec: V1PoolMock
  let module: BurnV1LiquidityModule
  const EODEC = 1640995199
  const EOSEP = 1633046399

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  const baseId = DAI
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock

    // ==== Set v1 Mocks ====
    fyDaiSep = (await deployContract(ownerAcc, V1FYDaiMockArtifact, [
      base.address,
      EOSEP,
    ])) as V1FYDaiMock

    v1PoolSep = (await deployContract(ownerAcc, V1PoolMockArtifact, [
      base.address,
      fyDaiSep.address,
    ])) as V1PoolMock

    fyDaiDec = (await deployContract(ownerAcc, V1FYDaiMockArtifact, [
      base.address,
      EODEC,
    ])) as V1FYDaiMock
    
    v1PoolDec = (await deployContract(ownerAcc, V1PoolMockArtifact, [
      base.address,
      fyDaiDec.address,
    ])) as V1PoolMock

    // ==== Module ====

    module = (await deployContract(ownerAcc, BurnModuleArtifact, [
      v1PoolSep.address,
      v1PoolDec.address,
    ])) as BurnV1LiquidityModule
    
    await ladle.grantRoles([id(ladle.ladle.interface, 'addToken(address,bool)')], owner)
    await ladle.grantRoles([id(ladle.ladle.interface, 'addModule(address,bool)')], owner)

    await ladle.ladle.addToken(v1PoolSep.address, true)
    await ladle.ladle.addToken(v1PoolDec.address, true)
    await ladle.addModule(module.address, true)

    // ==== Initialize v1 pools ====

    await v1PoolSep.mint(owner, owner, WAD.mul(10))
    await fyDaiSep.approve(v1PoolSep.address, MAX256)
    await fyDaiSep.mint(owner, WAD)
    await v1PoolSep.sellFYDai(owner, owner, WAD)

    await v1PoolDec.mint(owner, owner, WAD.mul(10))
    await fyDaiDec.approve(v1PoolDec.address, MAX256)
    await fyDaiDec.mint(owner, WAD)
    await v1PoolDec.sellFYDai(owner, owner, WAD)

    // ==== Ladle approvals ====
    // I don't feel like messing with permits
    await v1PoolSep.approve(ladle.address, MAX256)
    await v1PoolDec.approve(ladle.address, MAX256)
  })

  it('redeems mature v1 fyDai', async () => {
    const poolTokensToBurn = (await v1PoolSep.balanceOf(owner)).div(2)
    const calldata = module.interface.encodeFunctionData('migrateLiquidity', [
      v1PoolSep.address, owner, poolTokensToBurn, 0
    ])
    await v1PoolSep.transfer(ladle.address, poolTokensToBurn)
    await ladle.moduleCall(module.address, calldata)
    expect(await base.balanceOf(owner)).to.not.equal(0)
  })

  it('sells v1 fyDai', async () => {
    const poolTokensToBurn = (await v1PoolDec.balanceOf(owner)).div(2)
    const calldata = module.interface.encodeFunctionData('migrateLiquidity', [
      v1PoolDec.address, owner, poolTokensToBurn, 0
    ])
    await v1PoolDec.transfer(ladle.address, poolTokensToBurn)
    await ladle.moduleCall(module.address, calldata)
    expect(await base.balanceOf(owner)).to.not.equal(0)
  })
})
