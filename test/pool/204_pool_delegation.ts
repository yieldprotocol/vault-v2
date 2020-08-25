const Pool = artifacts.require('Pool')

import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
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
    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year

    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai
    yDai1 = env.yDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })

    // Test setup

    // Allow owner to mint yDai the sneaky way, without recording a debt in controller
    await yDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(from, daiReserves, rate1)

      await dai.approve(pool.address, daiReserves, { from: from })
      await pool.init(daiReserves, { from: from })
    })

    it("doesn't mint liquidity without delegation", async () => {
      await expectRevert(pool.mint(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })

    it("doesn't burn liquidity without delegation", async () => {
      await expectRevert(pool.burn(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })

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

    it('buys dai with delegation', async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, yDaiTokens1, { from: owner })

      // yDaiInForChaiOut formula: https://www.desmos.com/calculator/16c4dgxhst

      assert.equal(
        await yDai1.balanceOf(from),
        yDaiTokens1.toString(),
        "'From' wallet should have " + yDaiTokens1 + ' yDai, instead has ' + (await yDai1.balanceOf(from))
      )

      await yDai1.approve(pool.address, yDaiTokens1, { from: from })
      await pool.addDelegate(operator, { from: from })
      await pool.buyDai(from, to, oneToken, { from: operator })

      assert.equal(await dai.balanceOf(to), oneToken.toString(), 'Receiver account should have 1 dai token')

      const expectedYDaiIn = new BN(oneToken.toString()).mul(new BN('10019')).div(new BN('10000')) // I just hate javascript
      const yDaiIn = new BN(yDaiTokens1.toString()).sub(new BN(await yDai1.balanceOf(from)))
      expect(yDaiIn).to.be.bignumber.gt(expectedYDaiIn.mul(new BN('9999')).div(new BN('10000')))
      // @ts-ignore
      expect(yDaiIn).to.be.bignumber.lt(expectedYDaiIn.mul(new BN('10001')).div(new BN('10000')))
    })

    it('sells yDai with delegation', async () => {
      const oneToken = toWad(1)
      await yDai1.mint(from, oneToken, { from: owner })

      // chaiOutForYDaiIn formula: https://www.desmos.com/calculator/6ylefi7fv7

      assert.equal(
        await dai.balanceOf(to),
        0,
        "'To' wallet should have no dai, instead has " + (await dai.balanceOf(to))
      )

      await yDai1.approve(pool.address, oneToken, { from: from })
      await pool.addDelegate(operator, { from: from })
      await pool.sellYDai(from, to, oneToken, { from: operator })

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

      it('mints liquidity tokens with delegation', async () => {
        const oneToken = toWad(1)
        await dai.mint(from, oneToken, { from: owner })
        await yDai1.mint(from, yDaiTokens1, { from: owner })

        const yDaiBefore = new BN(await yDai1.balanceOf(from))
        const poolTokensBefore = new BN(await pool.balanceOf(to))

        await dai.approve(pool.address, oneToken, { from: from })
        await yDai1.approve(pool.address, yDaiTokens1, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.mint(from, to, oneToken, { from: operator })

        const expectedMinted = new BN('1316595685900000000')
        const expectedYDaiIn = new BN('336985800550000000')

        const minted = new BN(await pool.balanceOf(to)).sub(poolTokensBefore)
        const yDaiIn = yDaiBefore.sub(new BN(await yDai1.balanceOf(from)))

        expect(minted).to.be.bignumber.gt(expectedMinted.mul(new BN('9999')).div(new BN('10000')))
        expect(minted).to.be.bignumber.lt(expectedMinted.mul(new BN('10001')).div(new BN('10000')))

        expect(yDaiIn).to.be.bignumber.gt(expectedYDaiIn.mul(new BN('9999')).div(new BN('10000')))
        expect(yDaiIn).to.be.bignumber.lt(expectedYDaiIn.mul(new BN('10001')).div(new BN('10000')))
      })

      it('burns liquidity tokens', async () => {
        const oneToken = toWad(1)
        const yDaiReservesBefore = new BN(await yDai1.balanceOf(pool.address))
        const daiReservesBefore = new BN(await dai.balanceOf(pool.address))

        await pool.approve(pool.address, oneToken, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.burn(from, to, oneToken, { from: operator })

        const expectedYDaiOut = new BN('255952380950000000')
        const expectedDaiOut = new BN('759534616990000000')

        const yDaiOut = yDaiReservesBefore.sub(new BN(await yDai1.balanceOf(pool.address)))
        const daiOut = daiReservesBefore.sub(new BN(await dai.balanceOf(pool.address)))

        expect(yDaiOut).to.be.bignumber.gt(expectedYDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(yDaiOut).to.be.bignumber.lt(expectedYDaiOut.mul(new BN('10001')).div(new BN('10000')))

        expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
      })

      it('sells dai with delegation', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // yDaiOutForChaiIn formula: https://www.desmos.com/calculator/dcjuj5lmmc

        assert.equal(
          await yDai1.balanceOf(to),
          0,
          "'To' wallet should have no yDai, instead has " + (await yDai1.balanceOf(operator))
        )

        await dai.approve(pool.address, oneToken, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.sellDai(from, to, oneToken, { from: operator })

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

      it('buys yDai with delegation', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // chaiInForYDaiOut formula: https://www.desmos.com/calculator/cgpfpqe3fq

        assert.equal(
          await yDai1.balanceOf(to),
          0,
          "'To' wallet should have no yDai, instead has " + (await yDai1.balanceOf(to))
        )

        await dai.approve(pool.address, daiTokens1, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.buyYDai(from, to, oneToken, { from: operator })

        assert.equal(await yDai1.balanceOf(to), oneToken.toString(), "'To' wallet should have 1 yDai token")

        const expectedDaiIn = new BN(oneToken.toString()).mul(new BN('8835')).div(new BN('10000')) // I just hate javascript
        const daiIn = new BN(daiTokens1.toString()).sub(new BN(await dai.balanceOf(from)))
        // @ts-ignore
        expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')))
        // @ts-ignore
        expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')))
      })
    })
  })
})
