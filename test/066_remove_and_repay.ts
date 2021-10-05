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
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    await baseJoin.grantRoles(
      [id(baseJoin.interface, 'join(address,uint128)'), id(baseJoin.interface, 'exit(address,uint128)')],
      owner
    )

    // Borrow and add liquidity
    await ladle.serve(vaultId, pool.address, WAD, WAD, MAX)
    await ladle.pour(vaultId, pool.address, WAD.mul(4), WAD.mul(4))
    await pool.mint(owner, true, 0)

    // Add some base to the baseJoin to serve redemptions
    await base.mint(baseJoin.address, WAD.mul(3))
    await baseJoin.join(owner, WAD.mul(3))
  })

  it('repays debt with fyToken, returns base and surplus fyToken', async () => {
    const baseReservesBefore = await base.balanceOf(pool.address)
    const fyTokenReservesBefore = await fyToken.balanceOf(pool.address)
    const baseBalanceBefore = await base.balanceOf(owner)
    const fyTokenBalanceBefore = await fyToken.balanceOf(owner)
    const debtBefore = (await cauldron.balances(vaultId)).art

    await pool.transfer(pool.address, WAD.mul(2))

    const burnCall = pool.interface.encodeFunctionData('burn', [owner, ladle.address, 0, 0])

    await ladle.batch([
      ladle.routeAction(pool.address, burnCall), // burn to ladle
      ladle.repayFromLadleAction(vaultId, owner), // repay with fyToken
    ])

    const baseOut = baseReservesBefore.sub(await base.balanceOf(pool.address))
    const fyTokenOut = fyTokenReservesBefore.sub(await fyToken.balanceOf(pool.address))
    const debtRepaid = debtBefore.sub((await cauldron.balances(vaultId)).art)
    const baseObtained = (await base.balanceOf(owner)).sub(baseBalanceBefore)
    const fyTokenObtained = (await fyToken.balanceOf(owner)).sub(fyTokenBalanceBefore)
    expect(fyTokenOut).to.equal(debtRepaid.add(fyTokenObtained))
    expect(baseObtained).to.equal(baseOut)
  })

  it('repays debt with base, returns base and surplus fyToken', async () => {
    const baseReservesBefore = await base.balanceOf(pool.address)
    const fyTokenReservesBefore = await fyToken.balanceOf(pool.address)
    const baseBalanceBefore = await base.balanceOf(owner)
    const fyTokenBalanceBefore = await fyToken.balanceOf(owner)
    const debtBefore = (await cauldron.balances(vaultId)).art

    await pool.transfer(pool.address, WAD.mul(2))

    const burnCall = pool.interface.encodeFunctionData('burn', [ladle.address, owner, 0, 0])

    await ladle.batch([
      ladle.routeAction(pool.address, burnCall), // burn to ladle
      ladle.closeFromLadleAction(vaultId, owner), // close with base
    ])

    const baseOut = baseReservesBefore.sub(await base.balanceOf(pool.address))
    const fyTokenOut = fyTokenReservesBefore.sub(await fyToken.balanceOf(pool.address))
    const debtRepaid = await cauldron.callStatic.debtToBase(
      seriesId,
      debtBefore.sub((await cauldron.balances(vaultId)).art)
    )
    const baseObtained = (await base.balanceOf(owner)).sub(baseBalanceBefore)
    const fyTokenObtained = (await fyToken.balanceOf(owner)).sub(fyTokenBalanceBefore)
    expect(baseOut).to.equal(debtRepaid.add(baseObtained))
    expect(fyTokenObtained).to.equal(fyTokenOut)
  })

  describe('after maturity', async () => {
    beforeEach(async () => {
      await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
    })

    it('redeems fyToken, returns base', async () => {
      const baseReservesBefore = await base.balanceOf(pool.address)
      const joinReservesBefore = await base.balanceOf(baseJoin.address)
      const fyTokenReservesBefore = await fyToken.balanceOf(pool.address)
      const fyTokenSupplyBefore = await fyToken.totalSupply()
      const baseBalanceBefore = await base.balanceOf(owner)

      await pool.transfer(pool.address, WAD.mul(2))
      const burnCall = pool.interface.encodeFunctionData('burn', [owner, ladle.address, 0, 0])

      await ladle.batch([
        ladle.routeAction(pool.address, burnCall), // burn to ladle
        ladle.redeemAction(seriesId, owner, 0), // ladle redeem
      ])

      const baseOut = baseReservesBefore.sub(await base.balanceOf(pool.address))
      const fyTokenSupply = await fyToken.totalSupply()
      const fyTokenRedeemed = fyTokenSupplyBefore.sub(await fyToken.totalSupply())
      const baseServed = joinReservesBefore.sub(await base.balanceOf(baseJoin.address))

      const baseObtained = (await base.balanceOf(owner)).sub(baseBalanceBefore)
      expect(baseObtained).to.equal(baseOut.add(baseServed))
      expect(fyTokenSupply).to.equal(fyTokenSupplyBefore.sub(fyTokenRedeemed))
    })
  })
})
