const Pool = artifacts.require('Pool')
const LimitPool = artifacts.require('LimitPool')

import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { toWad, toRay, mulRay } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('LimitPool', async (accounts) => {
  let [owner, user1, operator, from, to] = accounts

  // These values impact the pool results
  const rate1 = toRay(1.4)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const yDaiTokens1 = daiTokens1

  let maturity1: number
  let yDai1: Contract
  let limitPool: Contract
  let pool: Contract
  let dai: Contract
  let env: YieldEnvironmentLite

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai
    yDai1 = env.yDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup LimitPool
    limitPool = await LimitPool.new(pool.address, { from: owner })

    // Allow owner to mint yDai the sneaky way, without recording a debt in controller
    await yDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)

      await dai.approve(pool.address, daiReserves, { from: user1 })
      await pool.init(daiReserves, { from: user1 })
    })

    it('buys dai', async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, yDaiTokens1, { from: owner })

      await pool.addDelegate(limitPool.address, { from: from })
      await yDai1.approve(pool.address, yDaiTokens1, { from: from })
      await limitPool.buyDai(pool.address, to, oneToken, oneToken.mul(2), { from: from })

      const expectedYDaiIn = new BN(oneToken.toString()).mul(new BN('10019')).div(new BN('10000')) // I just hate javascript
      const yDaiIn = new BN(yDaiTokens1.toString()).sub(new BN(await yDai1.balanceOf(from)))
      expect(yDaiIn).to.be.bignumber.gt(expectedYDaiIn.mul(new BN('9999')).div(new BN('10000')))
      expect(yDaiIn).to.be.bignumber.lt(expectedYDaiIn.mul(new BN('10001')).div(new BN('10000')))
    })

    it("doesn't buy dai if limit exceeded", async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, yDaiTokens1, { from: owner })

      await pool.addDelegate(limitPool.address, { from: from })
      await yDai1.approve(pool.address, yDaiTokens1, { from: from })

      await expectRevert(
        limitPool.buyDai(pool.address, to, oneToken, oneToken.div(2), { from: from }),
        'LimitPool: Limit exceeded'
      )
    })

    it('sells yDai', async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, oneToken, { from: owner })

      await pool.addDelegate(limitPool.address, { from: from })
      await yDai1.approve(pool.address, oneToken, { from: from })
      await limitPool.sellYDai(pool.address, to, oneToken, oneToken.div(2), { from: from })

      assert.equal(await yDai1.balanceOf(from), 0, "'From' wallet should have no yDai tokens")

      const expectedDaiOut = new BN(oneToken.toString()).mul(new BN('99814')).div(new BN('100000')) // I just hate javascript
      const daiOut = new BN(await dai.balanceOf(to))
      expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
    })

    it("doesn't sell yDai if limit not reached", async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, oneToken, { from: owner })

      await pool.addDelegate(limitPool.address, { from: from })
      await yDai1.approve(pool.address, oneToken, { from: from })

      await expectRevert(
        limitPool.sellYDai(pool.address, to, oneToken, oneToken.mul(2), { from: from }),
        'LimitPool: Limit not reached'
      )
    })

    describe('with extra yDai reserves', () => {
      beforeEach(async () => {
        const additionalYDaiReserves = toWad(34.4)
        await yDai1.mint(operator, additionalYDaiReserves, { from: owner })
        await yDai1.approve(pool.address, additionalYDaiReserves, { from: operator })
        await pool.sellYDai(operator, operator, additionalYDaiReserves, { from: operator })
      })

      it('sells dai', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        await pool.addDelegate(limitPool.address, { from: from })
        await dai.approve(pool.address, oneToken, { from: from })
        await limitPool.sellDai(pool.address, to, oneToken, oneToken.div(2), { from: from })

        assert.equal(
          await dai.balanceOf(from),
          daiTokens1.sub(oneToken).toString(),
          "'From' wallet should have " + daiTokens1.sub(oneToken) + ' dai tokens'
        )

        const expectedYDaiOut = new BN(oneToken.toString()).mul(new BN('1132')).div(new BN('1000')) // I just hate javascript
        const yDaiOut = new BN(await yDai1.balanceOf(to))
        // This is the lowest precision achieved.
        expect(yDaiOut).to.be.bignumber.gt(expectedYDaiOut.mul(new BN('999')).div(new BN('1000')))
        expect(yDaiOut).to.be.bignumber.lt(expectedYDaiOut.mul(new BN('1001')).div(new BN('1000')))
      })

      it("doesn't sell dai if limit not reached", async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        await pool.addDelegate(limitPool.address, { from: from })
        await dai.approve(pool.address, oneToken, { from: from })

        await expectRevert(
          limitPool.sellDai(pool.address, to, oneToken, oneToken.mul(2), { from: from }),
          'LimitPool: Limit not reached'
        )
      })

      it('buys yDai', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        await pool.addDelegate(limitPool.address, { from: from })
        await dai.approve(pool.address, daiTokens1, { from: from })
        await limitPool.buyYDai(pool.address, to, oneToken, oneToken.mul(2), { from: from })

        assert.equal(await yDai1.balanceOf(to), oneToken.toString(), "'To' wallet should have 1 yDai token")

        const expectedDaiIn = new BN(oneToken.toString()).mul(new BN('8835')).div(new BN('10000')) // I just hate javascript
        const daiIn = new BN(daiTokens1.toString()).sub(new BN(await dai.balanceOf(from)))
        expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')))
        expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')))
      })

      it("doesn't buy yDai if limit exceeded", async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        await pool.addDelegate(limitPool.address, { from: from })
        await dai.approve(pool.address, daiTokens1, { from: from })

        await expectRevert(
          limitPool.buyYDai(pool.address, to, oneToken, oneToken.div(2), { from: from }),
          'LimitPool: Limit exceeded'
        )
      })
    })
  })
})
