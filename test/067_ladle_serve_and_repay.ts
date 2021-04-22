import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD, MAX128 } = constants
const MAX = MAX128

import { OPS } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { PoolMock } from '../typechain/PoolMock'
import { PoolRouterMock } from '../typechain/PoolRouterMock'
import { ERC20Mock } from '../typechain/ERC20Mock'

import PoolRouterMockArtifact from '../artifacts/contracts/mocks/PoolRouterMock.sol/PoolRouterMock.json'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment, LadleWrapper } from './shared/fixtures'

describe('Ladle - serve and repay', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let pool: PoolMock
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ladle: LadleWrapper

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = new LadleWrapper(env.ladle)
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
  })

  it('borrows an amount of base', async () => {
    const baseBalanceBefore = await base.balanceOf(other)
    const ilkBalanceBefore = await ilk.balanceOf(owner)
    const baseBorrowed = WAD
    const expectedDebtInFY = baseBorrowed.mul(105).div(100)
    const inkPosted = WAD.mul(2)

    await expect(await ladle.serve(vaultId, other, inkPosted, baseBorrowed, MAX))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, inkPosted, expectedDebtInFY)
      .to.emit(pool, 'Trade')
      .withArgs(await fyToken.maturity(), ladle.address, other, baseBorrowed.mul(-1), expectedDebtInFY)
    expect((await cauldron.balances(vaultId)).ink).to.equal(inkPosted)
    expect((await cauldron.balances(vaultId)).art).to.equal(expectedDebtInFY)
    expect(await base.balanceOf(other)).to.equal(baseBalanceBefore.add(baseBorrowed))
    expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.sub(inkPosted))
  })

  it('repays debt with base', async () => {
    await ladle.pour(vaultId, owner, WAD, WAD)

    const baseBalanceBefore = await base.balanceOf(owner)
    const debtRepaidInBase = WAD.div(2)
    const debtRepaidInFY = debtRepaidInBase.mul(105).div(100)
    const inkRetrieved = WAD.div(4)

    await base.transfer(pool.address, debtRepaidInBase) // This would normally be part of a multicall, using ladle.transferToPool
    await expect(await ladle.repay(vaultId, owner, inkRetrieved, 0))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, inkRetrieved, debtRepaidInFY.mul(-1))
      .to.emit(pool, 'Trade')
      .withArgs(await fyToken.maturity(), ladle.address, fyToken.address, debtRepaidInBase, debtRepaidInFY.mul(-1))
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD.sub(debtRepaidInFY))
    expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(debtRepaidInBase))
  })

  it('repays debt with base in a batch', async () => {
    await ladle.pour(vaultId, owner, WAD, WAD)

    const baseBalanceBefore = await base.balanceOf(owner)
    const debtRepaidInBase = WAD.div(2)
    const debtRepaidInFY = debtRepaidInBase.mul(105).div(100)
    const inkRetrieved = WAD.div(4)

    const transferToPoolData = ethers.utils.defaultAbiCoder.encode(['bool', 'uint128'], [true, debtRepaidInBase])
    const repayData = ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'uint128'], [owner, inkRetrieved, 0])

    await base.approve(ladle.address, debtRepaidInBase) // This would normally be part of a multicall, using ladle.forwardPermit
    await expect(ladle.batch(vaultId, [OPS.TRANSFER_TO_POOL, OPS.REPAY], [transferToPoolData, repayData]))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, inkRetrieved, debtRepaidInFY.mul(-1))
      .to.emit(pool, 'Trade')
      .withArgs(await fyToken.maturity(), ladle.address, fyToken.address, debtRepaidInBase, debtRepaidInFY.mul(-1))
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD.sub(debtRepaidInFY))
    expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(debtRepaidInBase))
  })

  it('repays all debt of a vault with base', async () => {
    await ladle.pour(vaultId, owner, WAD, WAD)

    const baseBalanceBefore = await base.balanceOf(owner)
    const baseOffered = WAD.mul(2)
    const debtinFY = WAD
    const debtinBase = debtinFY.mul(100).div(105)
    const inkRetrieved = WAD.div(4)

    await base.transfer(pool.address, baseOffered) // This would normally be part of a multicall, using ladle.transferToPool
    await expect(await ladle.repayVault(vaultId, owner, inkRetrieved, MAX))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, inkRetrieved, WAD.mul(-1))
      .to.emit(pool, 'Trade')
      .withArgs(await fyToken.maturity(), ladle.address, fyToken.address, debtinBase, debtinFY.mul(-1))
    await pool.retrieveBaseToken(owner)

    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(debtinBase))
  })

  it('repays all debt of a vault with base in a batch', async () => {
    // We need to set up a pool router
    const poolRouter = (await deployContract(ownerAcc, PoolRouterMockArtifact, [])) as PoolRouterMock
    await poolRouter.addPool(base.address, fyToken.address, pool.address)
    await ladle.ladle.setPoolRouter(poolRouter.address) // TODO: Use `set` or use constructor

    // Borrow, so that we can repay
    await ladle.pour(vaultId, owner, WAD, WAD)

    const baseBalanceBefore = await base.balanceOf(owner)
    const baseOffered = WAD.mul(2)
    const debtinFY = WAD
    const debtInBase = debtinFY.mul(100).div(105)
    const inkRetrieved = WAD.div(4)

    const transferToPoolData = ethers.utils.defaultAbiCoder.encode(['bool', 'uint128'], [true, baseOffered])
    const repayVaultData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'int128', 'uint128'],
      [owner, inkRetrieved, MAX]
    )

    // Call wrapping: ladle.route(poolRouter.route(findPool(base.address, fyToken.address).retrieveBaseTokenCall(owner)))
    const retrieveBaseTokenCall = pool.interface.encodeFunctionData('retrieveBaseToken', [owner]) // This is a call passed through `poolRouter.route`
    const poolRouteCall = poolRouter.interface.encodeFunctionData('route', [
      base.address,
      fyToken.address,
      retrieveBaseTokenCall,
    ]) // This is a call passed through `ladle.batch(OPS.ROUTE)`

    await base.approve(ladle.address, baseOffered) // This would normally be part of a multicall, using ladle.forwardPermit
    await expect(
      ladle.batch(
        vaultId,
        [OPS.TRANSFER_TO_POOL, OPS.REPAY_VAULT, OPS.ROUTE],
        [transferToPoolData, repayVaultData, poolRouteCall]
      )
    )
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, inkRetrieved, WAD.mul(-1))
      .to.emit(pool, 'Trade')
      .withArgs(await fyToken.maturity(), ladle.address, fyToken.address, debtInBase, debtinFY.mul(-1))

    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(debtInBase))
  })
})
