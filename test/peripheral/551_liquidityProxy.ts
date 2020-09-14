const Pool = artifacts.require('Pool')
const LiquidityProxy = artifacts.require('YieldProxy')

import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
import {
  CHAI,
  chi1,
  rate1,
  daiTokens1,
  chaiTokens1,
  toWad,
  toRay,
  divrup,
  precision,
  bnify,
  ZERO,
} from '../shared/utils'
import { MakerEnvironment, YieldEnvironmentLite, Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'
import { BigNumber } from 'ethers'

contract('YieldProxy - LiquidityProxy', async (accounts) => {
  let [owner, user1, operator, user2, to] = accounts

  const initialDai = daiTokens1

  let snapshot: any
  let snapshotId: string

  let maker: MakerEnvironment
  let env: YieldEnvironmentLite
  let treasury: Contract
  let controller: Contract

  let dai: Contract
  let chai: Contract
  let pool: Contract
  let eDai1: Contract
  let proxy: Contract

  let maturity1: number

  const daiIn = (daiReserves: BigNumber, eDaiReserves: BigNumber, daiUsed: BigNumber): BigNumber => {
    return daiUsed.mul(daiReserves).div(daiReserves.add(eDaiReserves))
  }

  const eDaiIn = (daiReserves: BigNumber, eDaiReserves: BigNumber, daiUsed: BigNumber): BigNumber => {
    return daiUsed.mul(eDaiReserves).div(daiReserves.add(eDaiReserves))
  }

  const postedIn = (expectedDebt: BigNumber, chi: BigNumber): BigNumber => {
    return divrup(expectedDebt.mul(toRay(1)), bnify(chi))
  }

  const mintedOut = (poolSupply: BigNumber, daiIn: BigNumber, daiReserves: BigNumber): BigNumber => {
    return poolSupply.mul(daiIn).div(daiReserves)
  }

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup eDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year

    env = await YieldEnvironmentLite.setup([maturity1])
    maker = env.maker
    dai = env.maker.dai
    chai = env.maker.chai
    treasury = env.treasury
    controller = env.controller
    eDai1 = env.eDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, eDai1.address, 'Name', 'Symbol', { from: owner })

    // Allow owner to mint eDai the sneaky way, without recording a debt in controller
    await eDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })

    // Setup LiquidityProxy
    proxy = await LiquidityProxy.new(env.controller.address, [pool.address])

    const MAX = bnify('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
    await env.maker.chai.approve(proxy.address, MAX, { from: user1 })
    await dai.approve(proxy.address, MAX, { from: user1 })
    await dai.approve(pool.address, MAX, { from: user1 })
    await controller.addDelegate(proxy.address, { from: user1 })
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  describe('with initial liquidity', () => {
    beforeEach(async () => {
      await env.maker.getDai(user1, initialDai, rate1)
      await dai.approve(pool.address, initialDai, { from: user1 })
      await pool.init(initialDai, { from: user1 })
      const additionalEDaiReserves = toWad(34.4)
      await eDai1.mint(operator, additionalEDaiReserves, { from: owner })
      await eDai1.approve(pool.address, additionalEDaiReserves, { from: operator })
      await pool.sellEDai(operator, operator, additionalEDaiReserves, { from: operator })

      await controller.addDelegate(proxy.address, { from: user2 })
    })

    it('mints liquidity tokens with dai only', async () => {
      const oneToken = toWad(1)

      const poolTokensBefore = bnify((await pool.balanceOf(user2)).toString())
      const maxEDai = oneToken

      const daiReserves = bnify((await dai.balanceOf(pool.address)).toString())
      const eDaiReserves = bnify((await eDai1.balanceOf(pool.address)).toString())
      const daiUsed = bnify(oneToken)
      const poolSupply = bnify((await pool.totalSupply()).toString())

      // console.log('          adding liquidity...')
      // console.log('          daiReserves: %d', daiReserves.toString())    // d_0
      // console.log('          eDaiReserves: %d', eDaiReserves.toString())  // y_0
      // console.log('          daiUsed: %d', daiUsed.toString())            // d_used

      // https://www.desmos.com/calculator/bl2knrktlt
      const expectedDaiIn = daiIn(daiReserves, eDaiReserves, daiUsed) // d_in
      const expectedDebt = eDaiIn(daiReserves, eDaiReserves, daiUsed) // y_in
      // console.log('          expected daiIn: %d', expectedDaiIn)
      // console.log('          expected eDaiIn: %d', expectedDebt)

      // console.log('          chi: %d', chi1)
      const expectedPosted = postedIn(expectedDebt, chi1)
      // console.log('          expected posted: %d', expectedPosted)         // p_chai

      // https://www.desmos.com/calculator/w9qorhrjbw
      // console.log('          Pool supply: %d', poolSupply)                 // s
      const expectedMinted = mintedOut(poolSupply, expectedDaiIn, daiReserves) // m
      // console.log('          expected minted: %d', expectedMinted)

      await dai.mint(user2, oneToken, { from: owner })
      await dai.approve(proxy.address, oneToken, { from: user2 })
      await proxy.addLiquidity(pool.address, daiUsed, maxEDai, { from: user2 })

      const debt = bnify((await controller.debtEDai(CHAI, maturity1, user2)).toString())
      const posted = bnify((await controller.posted(CHAI, user2)).toString())
      const minted = bnify((await pool.balanceOf(user2)).toString()).sub(poolTokensBefore)

      //asserts
      assert.equal(
        debt.toString(),
        expectedDebt.toString(),
        'User2 should have ' + expectedDebt + ' eDai debt, instead has ' + debt.toString()
      )
      assert.equal(
        posted.toString(),
        expectedPosted.toString(),
        'User2 should have ' + expectedPosted + ' posted chai, instead has ' + posted.toString()
      )
      assert.equal(
        minted.toString(),
        expectedMinted.toString(),
        'User2 should have ' + expectedMinted + ' pool tokens, instead has ' + minted.toString()
      )
      // Proxy doesn't keep dai (beyond rounding)
      expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      // Proxy doesn't keep eDai (beyond rounding)
      expect(await eDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      // Proxy doesn't keep liquidity (beyond rounding)
      expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
    })

    it('does not allow borrowing more than max amount', async () => {
      const oneToken = bnify(toWad(1))

      await dai.mint(user2, oneToken, { from: owner })
      await dai.approve(proxy.address, oneToken, { from: user2 })
      await expectRevert(proxy.addLiquidity(pool.address, oneToken, 1, { from: user2 }), 'YieldProxy: maxEDai exceeded')
    })

    describe('with proxied liquidity', () => {
      beforeEach(async () => {
        // Add liquidity to the pool
        const additionalEDai = toWad(34.4)
        await eDai1.mint(operator, additionalEDai, { from: owner })
        await eDai1.approve(pool.address, additionalEDai, { from: operator })
        await pool.sellEDai(operator, operator, additionalEDai, { from: operator })

        // Give some pool tokens to user2
        const oneToken = bnify(toWad(1))
        const maxBorrow = oneToken
        await dai.mint(user2, oneToken, { from: owner })
        await dai.approve(proxy.address, oneToken, { from: user2 })
        await proxy.addLiquidity(pool.address, oneToken, maxBorrow, { from: user2 })

        // Add some funds to the system to allow for rounding losses when withdrawing chai
        await maker.getChai(owner, 1000, chi1, rate1) // getChai can't get very small amounts
        await chai.approve(treasury.address, precision, { from: owner })
        await controller.post(CHAI, owner, owner, precision, { from: owner })
      })

      it('removes liquidity early by selling', async () => {
        // This scenario replicates a user with more debt that can be repaid by burning liquidity tokens.
        // It uses the pool to sell the obtained Dai, so it should be used when the pool rate is better than 1:1.
        // Sells once, repays once, and does nothing else so the gas cost is 178K.

        // Create some debt, so that there is no EDai from the burn left to sell.
        await maker.getChai(user2, chaiTokens1, chi1, rate1)
        await chai.approve(treasury.address, chaiTokens1, { from: user2 })
        await controller.post(CHAI, user2, user2, chaiTokens1, { from: user2 })
        const toBorrow = (await env.unlockedOf(CHAI, user2)).toString()
        await controller.borrow(CHAI, maturity1, user2, user2, toBorrow, { from: user2 })

        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtEDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(ZERO)
        // Has eDai debt
        expect(debt).to.be.bignumber.gt(ZERO)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Has eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(toBorrow)

        // the proxy must be a delegate in the pool because in order to remove
        // liquidity via the proxy we must authorize the proxy to burn from our balance
        await pool.addDelegate(proxy.address, { from: user2 })
        await proxy.removeLiquidityEarlyDaiPool(pool.address, poolTokens, '0', '0', { from: user2 }) // TODO: Test limits

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Has less eDai debt
        expect(await controller.debtEDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Doesn't have dai
        expect(await dai.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Has the same eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(toBorrow)
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep eDai (beyond rounding)
        expect(await eDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })

      it('removes liquidity early by selling, with some eDai being sold in the pool', async () => {
        // This scenario replicates a user with debt that can be repaid by burning liquidity tokens.
        // It uses the pool to sell the obtained Dai, so it should be used when the pool rate is better than 1:1.
        // Sells twice, repays once, and and withdraws, so the gas cost is about 400K.

        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtEDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(ZERO)
        // Has eDai debt
        expect(debt).to.be.bignumber.gt(ZERO)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)

        // the proxy must be a delegate in the pool because in order to remove
        // liquidity via the proxy we must authorize the proxy to burn from our balance
        await pool.addDelegate(proxy.address, { from: user2 })
        await proxy.removeLiquidityEarlyDaiPool(pool.address, poolTokens, '0', '0', { from: user2 }) // TODO: Test limits

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Has less eDai debt
        expect(await controller.debtEDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Has more dai
        expect(await dai.balanceOf(user2)).to.be.bignumber.gt(daiBalance)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep eDai (beyond rounding)
        expect(await eDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })

      it('removes liquidity early by repaying, and uses all in paying debt', async () => {
        // This scenario replicates a user with more debt that can be repaid with eDai and Dai obtained by burning liquidity tokens.
        // It repays with Dai at the Controller, so it should be used when the pool rate is worse than 1:1.
        // Repays eDai and Dai, sells or withdraws withdraws nothing so the gas cost is 300K.

        // Create some debt, so that there is no EDai from the burn left to sell.
        await maker.getChai(user2, chaiTokens1, chi1, rate1)
        await chai.approve(treasury.address, chaiTokens1, { from: user2 })
        await controller.post(CHAI, user2, user2, chaiTokens1, { from: user2 })
        const toBorrow = (await env.unlockedOf(CHAI, user2)).toString()
        await controller.borrow(CHAI, maturity1, user2, user2, toBorrow, { from: user2 })

        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtEDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(ZERO)
        // Has eDai debt
        expect(debt).to.be.bignumber.gt(ZERO)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Has eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(toBorrow)

        // the proxy must be a delegate in the pool because in order to remove
        // liquidity via the proxy we must authorize the proxy to burn from our balance
        await pool.addDelegate(proxy.address, { from: user2 })
        await proxy.removeLiquidityEarlyDaiFixed(pool.address, poolTokens, '0', { from: user2 }) // TODO: Test limits

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Has less eDai debt
        expect(await controller.debtEDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Has the same eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(toBorrow)
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep eDai (beyond rounding)
        expect(await eDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })

      it('removes liquidity early by repaying, and has Dai left', async () => {
        // This scenario replicates a user with debt that can be repaid with eDai and Dai obtained by burning liquidity tokens.
        // It repays with Dai at the Controller, so it should be used when the pool rate is worse than 1:1.
        // Repays eDai and Dai, withdraws Dai and Chai so the gas cost is 394K.

        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtEDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(ZERO)
        // Has eDai debt
        expect(debt).to.be.bignumber.gt(ZERO)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)

        // the proxy must be a delegate in the pool because in order to remove
        // liquidity via the proxy we must authorize the proxy to burn from our balance
        await pool.addDelegate(proxy.address, { from: user2 })
        await proxy.removeLiquidityEarlyDaiFixed(pool.address, poolTokens, '0', { from: user2 }) // TODO: Test limits

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Has less eDai debt
        expect(await controller.debtEDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Has more dai
        expect(await dai.balanceOf(user2)).to.be.bignumber.gt(daiBalance)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep eDai (beyond rounding)
        expect(await eDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })

      it('removes liquidity early by repaying, and has Dai and eDai left', async () => {
        // This scenario replicates a user with debt that can be repaid with eDai and Dai obtained by burning liquidity tokens.
        // It repays with Dai at the Controller, so it should be used when the pool rate is worse than 1:1.
        // Repays eDai, sells eDai, withdraws Dai and Chai so the gas cost is 333K.

        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtEDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(ZERO)
        // Has eDai debt
        expect(debt).to.be.bignumber.gt(ZERO)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)

        // Pay some debt, so that there is EDai from the burn left to sell.
        await eDai1.mint(user2, debt.div(new BN('2')), { from: owner })
        await controller.repayEDai(CHAI, maturity1, user2, user2, debt.div(new BN('2')), { from: user2 })

        // the proxy must be a delegate in the pool because in order to remove
        // liquidity via the proxy we must authorize the proxy to burn from our balance
        await pool.addDelegate(proxy.address, { from: user2 })
        await proxy.removeLiquidityEarlyDaiFixed(pool.address, poolTokens, '0', { from: user2 }) // TODO: Test limits

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Has less eDai debt
        expect(await controller.debtEDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Has more dai
        expect(await dai.balanceOf(user2)).to.be.bignumber.gt(daiBalance)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep eDai (beyond rounding)
        expect(await eDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })

      it("doesn't remove liquidity if minimum prices not achieved", async () => {
        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtEDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(ZERO)
        // Has eDai debt
        expect(debt).to.be.bignumber.gt(ZERO)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)

        // the proxy must be a delegate in the pool because in order to remove
        // liquidity via the proxy we must authorize the proxy to burn from our balance
        await pool.addDelegate(proxy.address, { from: user2 })
        await expectRevert(
          proxy.removeLiquidityEarlyDaiPool(pool.address, poolTokens, toRay(2), '0', { from: user2 }),
          'YieldProxy: minimumDaiPrice not reached'
        )
        await expectRevert(
          proxy.removeLiquidityEarlyDaiPool(pool.address, poolTokens, '0', toRay(2), { from: user2 }),
          'YieldProxy: minimumEDaiPrice not reached'
        )
      })

      it('removes liquidity after maturity by redeeming', async () => {
        await helper.advanceTime(31556952)
        await helper.advanceBlock()
        await eDai1.mature()

        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtEDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(ZERO)
        // Has eDai debt
        expect(debt).to.be.bignumber.gt(ZERO)
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(ZERO)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)

        await pool.addDelegate(proxy.address, { from: user2 })

        await proxy.removeLiquidityMature(pool.address, poolTokens, { from: user2 })

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Has less eDai debt
        expect(await controller.debtEDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Has more dai
        expect(await dai.balanceOf(user2)).to.be.bignumber.gt(daiBalance)
        // Doesn't have eDai
        expect(await eDai1.balanceOf(user2)).to.be.bignumber.eq(ZERO)
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep eDai (beyond rounding)
        expect(await eDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })
    })
  })
})
