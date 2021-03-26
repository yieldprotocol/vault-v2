import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { WAD, MAX128 as MAX } from './shared/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { PoolMock } from '../typechain/PoolMock'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Ladle - serve', function () {
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
  let ladle: Ladle

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
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
  })

  it('borrows an amount of base', async () => {
    const baseBalanceBefore = await base.balanceOf(other)
    const ilkBalanceBefore = await ilk.balanceOf(owner)
    const expectedDebt = WAD.mul(105).div(100)
    await expect(await ladle.serve(vaultId, other, WAD.mul(2), WAD, MAX))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD.mul(2), expectedDebt)
      .to.emit(pool, 'Trade')
      .withArgs(await fyToken.maturity(), ladle.address, other, WAD.mul(-1), expectedDebt)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD.mul(2))
    expect((await cauldron.balances(vaultId)).art).to.equal(expectedDebt)
    expect(await base.balanceOf(other)).to.equal(baseBalanceBefore.add(WAD))
    expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.sub(WAD.mul(2)))
  })

  it('repays debt with base', async () => {
    await ladle.pour(vaultId, owner, WAD, WAD)

    const baseBalanceBefore = await base.balanceOf(owner)
    const debtRepaidInBase = WAD.div(2)
    const debtRepaidInFY = debtRepaidInBase.mul(105).div(100)

    await base.transfer(pool.address, debtRepaidInBase) // This would normally be part of a multicall, using ladle.transferToPool
    await expect(await ladle.repay(vaultId, owner, debtRepaidInBase, 0))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, 0, debtRepaidInFY.mul(-1))
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

    await base.transfer(pool.address, baseOffered) // This would normally be part of a multicall, using ladle.transferToPool
    await expect(await ladle.repayVault(vaultId, owner, 0, MAX))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
      .to.emit(pool, 'Trade')
      .withArgs(await fyToken.maturity(), ladle.address, fyToken.address, debtinBase, debtinFY.mul(-1))
    await pool.retrieveBaseToken(owner)

    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(debtinBase))
  })
})
