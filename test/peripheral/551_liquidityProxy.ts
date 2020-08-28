const Pool = artifacts.require('Pool')
const LiquidityProxy = artifacts.require('YieldProxy')

import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
import { CHAI, chi1, rate1, daiTokens1, toWad, toRay, divrup, precision, bnify } from '../shared/utils'
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
  let yDai1: Contract
  let proxy: Contract

  let maturity1: number

  const daiIn = (daiReserves: BigNumber, yDaiReserves: BigNumber, daiUsed: BigNumber): BigNumber => {
    return daiUsed.mul(daiReserves).div(daiReserves.add(yDaiReserves))
  }

  const yDaiIn = (daiReserves: BigNumber, yDaiReserves: BigNumber, daiUsed: BigNumber): BigNumber => {
    return daiUsed.mul(yDaiReserves).div(daiReserves.add(yDaiReserves))
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

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year

    env = await YieldEnvironmentLite.setup([maturity1])
    maker = env.maker
    dai = env.maker.dai
    chai = env.maker.chai
    treasury = env.treasury
    controller = env.controller
    yDai1 = env.yDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })

    // Allow owner to mint yDai the sneaky way, without recording a debt in controller
    await yDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })

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
      const additionalYDaiReserves = toWad(34.4)
      await yDai1.mint(operator, additionalYDaiReserves, { from: owner })
      await yDai1.approve(pool.address, additionalYDaiReserves, { from: operator })
      await pool.sellYDai(operator, operator, additionalYDaiReserves, { from: operator })

      await controller.addDelegate(proxy.address, { from: user2 })
    })

    it('mints liquidity tokens with dai only', async () => {
      const oneToken = toWad(1)

      const poolTokensBefore = bnify((await pool.balanceOf(user2)).toString())
      const maxYDai = oneToken

      const daiReserves = bnify((await dai.balanceOf(pool.address)).toString())
      const yDaiReserves = bnify((await yDai1.balanceOf(pool.address)).toString())
      const daiUsed = bnify(oneToken)
      const poolSupply = bnify((await pool.totalSupply()).toString())

      // console.log('          adding liquidity...')
      // console.log('          daiReserves: %d', daiReserves.toString())    // d_0
      // console.log('          yDaiReserves: %d', yDaiReserves.toString())  // y_0
      // console.log('          daiUsed: %d', daiUsed.toString())            // d_used

      // https://www.desmos.com/calculator/bl2knrktlt
      const expectedDaiIn = daiIn(daiReserves, yDaiReserves, daiUsed) // d_in
      const expectedDebt = yDaiIn(daiReserves, yDaiReserves, daiUsed) // y_in
      // console.log('          expected daiIn: %d', expectedDaiIn)
      // console.log('          expected yDaiIn: %d', expectedDebt)

      // console.log('          chi: %d', chi1)
      const expectedPosted = postedIn(expectedDebt, chi1)
      // console.log('          expected posted: %d', expectedPosted)         // p_chai

      // https://www.desmos.com/calculator/w9qorhrjbw
      // console.log('          Pool supply: %d', poolSupply)                 // s
      const expectedMinted = mintedOut(poolSupply, expectedDaiIn, daiReserves) // m
      // console.log('          expected minted: %d', expectedMinted)

      await dai.mint(user2, oneToken, { from: owner })
      await dai.approve(proxy.address, oneToken, { from: user2 })
      await proxy.addLiquidity(pool.address, daiUsed, maxYDai, { from: user2 })

      const debt = bnify((await controller.debtYDai(CHAI, maturity1, user2)).toString())
      const posted = bnify((await controller.posted(CHAI, user2)).toString())
      const minted = bnify((await pool.balanceOf(user2)).toString()).sub(poolTokensBefore)

      //asserts
      assert.equal(
        debt.toString(),
        expectedDebt.toString(),
        'User2 should have ' + expectedDebt + ' yDai debt, instead has ' + debt.toString()
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
      // Proxy doesn't keep yDai (beyond rounding)
      expect(await yDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      // Proxy doesn't keep liquidity (beyond rounding)
      expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
    })

    it('does not allow borrowing more than max amount', async () => {
      const oneToken = bnify(toWad(1))

      await dai.mint(user2, oneToken, { from: owner })
      await dai.approve(proxy.address, oneToken, { from: user2 })
      await expectRevert(proxy.addLiquidity(pool.address, oneToken, 1, { from: user2 }), 'YieldProxy: maxYDai exceeded')
    })

    describe('with proxied liquidity', () => {
      beforeEach(async () => {
        // Add liquidity to the pool
        const additionalYDai = toWad(34.4)
        await yDai1.mint(operator, additionalYDai, { from: owner })
        await yDai1.approve(pool.address, additionalYDai, { from: operator })
        await pool.sellYDai(operator, operator, additionalYDai, { from: operator })

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
        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtYDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(new BN('0'))
        // Has yDai debt
        expect(debt).to.be.bignumber.gt(new BN('0'))
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(new BN('0'))
        // Doesn't have yDai
        expect(await yDai1.balanceOf(user2)).to.be.bignumber.eq(new BN('0'))

        // the proxy must be a delegate in the pool because in order to remove
        // liquidity via the proxy we must authorize the proxy to burn from our balance
        await pool.addDelegate(proxy.address, { from: user2 })
        await proxy.removeLiquidityEarly(pool.address, poolTokens, '0', { from: user2 })

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(new BN('0'))
        // Has less yDai debt
        expect(await controller.debtYDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Has more dai
        expect(await dai.balanceOf(user2)).to.be.bignumber.gt(daiBalance)
        // Doesn't have yDai
        expect(await yDai1.balanceOf(user2)).to.be.bignumber.eq(new BN('0'))
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep yDai (beyond rounding)
        expect(await yDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })

      it('removes liquidity after maturity by redeeming', async () => {
        await helper.advanceTime(31556952)
        await helper.advanceBlock()
        await yDai1.mature()

        const poolTokens = await pool.balanceOf(user2)
        const debt = await controller.debtYDai(CHAI, maturity1, user2)
        const daiBalance = await dai.balanceOf(user2)

        // Has pool tokens
        expect(poolTokens).to.be.bignumber.gt(new BN('0'))
        // Has yDai debt
        expect(debt).to.be.bignumber.gt(new BN('0'))
        // Doesn't have dai
        expect(daiBalance).to.be.bignumber.eq(new BN('0'))
        // Doesn't have yDai
        expect(await yDai1.balanceOf(user2)).to.be.bignumber.eq(new BN('0'))

        await pool.addDelegate(proxy.address, { from: user2 })

        await proxy.removeLiquidityMature(pool.address, poolTokens, { from: user2 })

        // Doesn't have pool tokens
        expect(await pool.balanceOf(user2)).to.be.bignumber.eq(new BN('0'))
        // Has less yDai debt
        expect(await controller.debtYDai(CHAI, maturity1, user2)).to.be.bignumber.lt(debt)
        // Has more dai
        expect(await dai.balanceOf(user2)).to.be.bignumber.gt(daiBalance)
        // Doesn't have yDai
        expect(await yDai1.balanceOf(user2)).to.be.bignumber.eq(new BN('0'))
        // Proxy doesn't keep dai (beyond rounding)
        expect(await dai.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep yDai (beyond rounding)
        expect(await yDai1.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
        // Proxy doesn't keep liquidity (beyond rounding)
        expect(await pool.balanceOf(proxy.address)).to.be.bignumber.lt(new BN('10'))
      })
    })
  })
})
