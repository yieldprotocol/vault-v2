const Pool = artifacts.require('Pool')

import { toWad, toRay, mulRay } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('Pool - Delegation', async (accounts) => {
  let [owner, user1, operator, from, to] = accounts

  // These values impact the pool results
  const rate1 = toRay(1.4)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const yDaiTokens1 = daiTokens1

  let maturity1: number
  let yDai1: Contract
  let dai: Contract
  let pool: Contract
  let env: Contract

  beforeEach(async () => {
    env = await YieldEnvironmentLite.setup()
    dai = env.maker.dai

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    yDai1 = await env.newYDai(maturity1, 'Name', 'Symbol')

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })

    // Test setup

    // Allow owner to mint yDai the sneaky way, without recording a debt in controller
    await yDai1.orchestrate(owner, { from: owner })
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)

      await dai.approve(pool.address, daiReserves, { from: user1 })
      await pool.init(daiReserves, { from: user1 })
    })

    it('buys dai without delegation', async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, yDaiTokens1, { from: owner })

      // yDaiInForChaiOut formula: https://www.desmos.com/calculator/16c4dgxhst

      assert.equal(
        await yDai1.balanceOf(from),
        yDaiTokens1.toString(),
        "'From' wallet should have " + yDaiTokens1 + ' yDai, instead has ' + (await yDai1.balanceOf(from))
      )

      await yDai1.approve(pool.address, yDaiTokens1, { from: from })
      await pool.buyDai(from, to, oneToken, { from: from })

      assert.equal(await dai.balanceOf(to), oneToken.toString(), 'Receiver account should have 1 dai token')

      const expectedYDaiIn = new BN(oneToken.toString()).mul(new BN('10019')).div(new BN('10000')) // I just hate javascript
      const yDaiIn = new BN(yDaiTokens1.toString()).sub(new BN(await yDai1.balanceOf(from)))
      expect(yDaiIn).to.be.bignumber.gt(expectedYDaiIn.mul(new BN('9999')).div(new BN('10000')))
      // @ts-ignore
      expect(yDaiIn).to.be.bignumber.lt(expectedYDaiIn.mul(new BN('10001')).div(new BN('10000')))
    })

    it('sells yDai without delegation', async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, oneToken, { from: owner })

      // chaiOutForYDaiIn formula: https://www.desmos.com/calculator/6ylefi7fv7

      assert.equal(
        await dai.balanceOf(to),
        0,
        "'To' wallet should have no dai, instead has " + (await dai.balanceOf(to))
      )

      await yDai1.approve(pool.address, oneToken, { from: from })
      await pool.sellYDai(from, to, oneToken, { from: from })

      assert.equal(await yDai1.balanceOf(from), 0, "'From' wallet should have no yDai tokens")

      const expectedDaiOut = new BN(oneToken.toString()).mul(new BN('99814')).div(new BN('100000')) // I just hate javascript
      const daiOut = new BN(await dai.balanceOf(to))
      // @ts-ignore
      expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
      // @ts-ignore
      expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
    })

    describe('with extra yDai reserves', () => {
      beforeEach(async () => {
        const additionalYDaiReserves = toWad(34.4)
        await yDai1.mint(operator, additionalYDaiReserves, { from: owner })
        await yDai1.approve(pool.address, additionalYDaiReserves, { from: operator })
        await pool.sellYDai(operator, operator, additionalYDaiReserves, { from: operator })
      })

      it('sells dai without delegation', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // yDaiOutForChaiIn formula: https://www.desmos.com/calculator/dcjuj5lmmc

        assert.equal(
          await yDai1.balanceOf(to),
          0,
          "'To' wallet should have no yDai, instead has " + (await yDai1.balanceOf(operator))
        )

        await dai.approve(pool.address, oneToken, { from: from })
        await pool.sellDai(from, to, oneToken, { from: from })

        assert.equal(
          await dai.balanceOf(from),
          daiTokens1.sub(oneToken).toString(),
          "'From' wallet should have " + daiTokens1.sub(oneToken) + ' dai tokens'
        )

        const expectedYDaiOut = new BN(oneToken.toString()).mul(new BN('1132')).div(new BN('1000')) // I just hate javascript
        const yDaiOut = new BN(await yDai1.balanceOf(to))
        // This is the lowest precision achieved.
        // @ts-ignore
        expect(yDaiOut).to.be.bignumber.gt(expectedYDaiOut.mul(new BN('999')).div(new BN('1000')))
        // @ts-ignore
        expect(yDaiOut).to.be.bignumber.lt(expectedYDaiOut.mul(new BN('1001')).div(new BN('1000')))
      })

      it('buys yDai without delegation', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // chaiInForYDaiOut formula: https://www.desmos.com/calculator/cgpfpqe3fq

        assert.equal(
          await yDai1.balanceOf(to),
          0,
          "'To' wallet should have no yDai, instead has " + (await yDai1.balanceOf(to))
        )

        await dai.approve(pool.address, daiTokens1, { from: from })
        await pool.buyYDai(from, to, oneToken, { from: from })

        assert.equal(await yDai1.balanceOf(to), oneToken.toString(), "'To' wallet should have 1 yDai token")

        const expectedDaiIn = new BN(oneToken.toString()).mul(new BN('8835')).div(new BN('10000')) // I just hate javascript
        const daiIn = new BN(daiTokens1.toString()).sub(new BN(await dai.balanceOf(from)))
        // @ts-ignore
        expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')))
        // @ts-ignore
        expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')))
      })
    })

    // --- ONLY HOLDER OR DELEGATE TESTS ---

    it("doesn't sell dai without delegation", async () => {
      await expectRevert(pool.sellDai(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })

    it("doesn't buy dai without delegation", async () => {
      await expectRevert(pool.buyDai(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })

    it("doesn't sell yDai without delegation", async () => {
      await expectRevert(pool.sellYDai(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })

    it("doesn't buy yDai without delegation", async () => {
      await expectRevert(pool.buyYDai(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })
  })
})
