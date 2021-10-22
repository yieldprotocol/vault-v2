import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants, id } from '@yield-protocol/utils-v2'
const { WAD, MAX128 } = constants
const MAX = MAX128
import { ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { PoolMock } from '../typechain/PoolMock'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - remove and repay', function () {
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
  let baseJoin: Join
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

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    baseJoin = env.joins.get(baseId) as Join
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(baseId) as string

    await baseJoin.grantRoles(
      [id(baseJoin.interface, 'join(address,uint128)'), id(baseJoin.interface, 'exit(address,uint128)')],
      owner
    )

    // Borrow and add liquidity
    // await ladle.serve(vaultId, pool.address, WAD, WAD, MAX)
    // await pool.mint(owner, true, 0)

    await ladle.pour(vaultId, pool.address, WAD.mul(4), WAD.mul(4))

    // Add some base to the baseJoin to serve redemptions and remainder returns
    await base.mint(baseJoin.address, WAD.mul(10))
    await baseJoin.join(owner, WAD.mul(10))
  })

  it('repays debt with fyToken, returns surplus', async () => {
    const baseBalanceBefore = await base.balanceOf(owner)
    const fyTokenBalanceBefore = await fyToken.balanceOf(owner)
    const artBefore = (await cauldron.balances(vaultId)).art
    const ilkBefore = (await cauldron.balances(vaultId)).ink

    await fyToken.mint(ladle.address, artBefore.div(2))
    await ladle.repayFromLadle(vaultId, owner)
    expect((await cauldron.balances(vaultId)).art).to.equal(artBefore.div(2))

    await fyToken.mint(ladle.address, artBefore)
    await ladle.repayFromLadle(vaultId, owner)
    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect((await base.balanceOf(owner)).sub(baseBalanceBefore)).to.equal(ilkBefore)
    expect((await fyToken.balanceOf(owner)).sub(fyTokenBalanceBefore)).to.equal(artBefore.div(2))
  })

  it('repays debt with base, returns surplus', async () => {
    const baseBalanceBefore = await base.balanceOf(owner)
    const debtBefore = await cauldron.callStatic.debtToBase(seriesId, (await cauldron.balances(vaultId)).art)
    const ilkBefore = (await cauldron.balances(vaultId)).ink

    await base.mint(ladle.address, debtBefore.div(2))
    await ladle.closeFromLadle(vaultId, owner) // close with base
    expect(await cauldron.callStatic.debtToBase(seriesId, (await cauldron.balances(vaultId)).art)).to.equal(
      debtBefore.div(2)
    )

    await base.mint(ladle.address, debtBefore)
    await ladle.closeFromLadle(vaultId, owner) // close with base
    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect((await base.balanceOf(owner)).sub(baseBalanceBefore)).to.equal(debtBefore.div(2).add(ilkBefore))
  })

  it('if there is no debt, returns fyToken', async () => {
    // Make a vault with no debt
    await fyToken.mint(ladle.address, (await cauldron.balances(vaultId)).art)
    await ladle.repayFromLadle(vaultId, owner)
    expect((await cauldron.balances(vaultId)).art).to.equal(0)

    const fyTokenBalanceBefore = await fyToken.balanceOf(owner)
    await fyToken.mint(ladle.address, WAD)
    await ladle.repayFromLadle(vaultId, owner)
    expect(await fyToken.balanceOf(owner)).to.equal(fyTokenBalanceBefore.add(WAD))
  })

  it('if there is no debt, returns base', async () => {
    // Make a vault with no debt
    await fyToken.mint(ladle.address, (await cauldron.balances(vaultId)).art)
    await ladle.repayFromLadle(vaultId, owner)
    expect((await cauldron.balances(vaultId)).art).to.equal(0)

    const baseBalanceBefore = await base.balanceOf(owner)
    await base.mint(ladle.address, WAD)
    await ladle.closeFromLadle(vaultId, owner) // close with base
    expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.add(WAD))
  })
})
