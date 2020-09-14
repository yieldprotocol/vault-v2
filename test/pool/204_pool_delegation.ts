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
  const rate1 = toRay(1.02)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const eDaiTokens1 = daiTokens1

  let maturity1: number
  let eDai1: Contract
  let dai: Contract
  let pool: Contract
  let env: Contract

  beforeEach(async () => {
    // Setup eDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year

    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai
    eDai1 = env.eDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, eDai1.address, 'Name', 'Symbol', { from: owner })

    // Test setup

    // Allow owner to mint eDai the sneaky way, without recording a debt in controller
    await eDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
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

    it("doesn't sell eDai without delegation", async () => {
      await expectRevert(pool.sellEDai(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })

    it("doesn't buy eDai without delegation", async () => {
      await expectRevert(pool.buyEDai(from, to, 1, { from: operator }), 'Pool: Only Holder Or Delegate')
    })

    it('buys dai with delegation', async () => {
      const oneToken = toWad(1)
      await eDai1.mint(from, eDaiTokens1, { from: owner })

      // eDaiInForChaiOut formula: https://www.desmos.com/calculator/c1scsshbzh

      assert.equal(
        await eDai1.balanceOf(from),
        eDaiTokens1.toString(),
        "'From' wallet should have " + eDaiTokens1 + ' eDai, instead has ' + (await eDai1.balanceOf(from))
      )

      await eDai1.approve(pool.address, eDaiTokens1, { from: from })
      await pool.addDelegate(operator, { from: from })
      await pool.buyDai(from, to, oneToken, { from: operator })

      assert.equal(await dai.balanceOf(to), oneToken.toString(), 'Receiver account should have 1 dai token')

      const expectedEDaiIn = new BN(oneToken.toString()).mul(new BN('100270')).div(new BN('100000'))
      const eDaiIn = new BN(eDaiTokens1.toString()).sub(new BN(await eDai1.balanceOf(from)))
      expect(eDaiIn).to.be.bignumber.gt(expectedEDaiIn.mul(new BN('9999')).div(new BN('10000')))
      // @ts-ignore
      expect(eDaiIn).to.be.bignumber.lt(expectedEDaiIn.mul(new BN('10001')).div(new BN('10000')))
    })

    it('sells eDai with delegation', async () => {
      const oneToken = toWad(1)
      await eDai1.mint(from, oneToken, { from: owner })

      // chaiOutForEDaiIn formula: https://www.desmos.com/calculator/7knilsjycu

      assert.equal(
        await dai.balanceOf(to),
        0,
        "'To' wallet should have no dai, instead has " + (await dai.balanceOf(to))
      )

      await eDai1.approve(pool.address, oneToken, { from: from })
      await pool.addDelegate(operator, { from: from })
      await pool.sellEDai(from, to, oneToken, { from: operator })

      assert.equal(await eDai1.balanceOf(from), 0, "'From' wallet should have no eDai tokens")

      const expectedDaiOut = new BN(oneToken.toString()).mul(new BN('99732')).div(new BN('100000'))
      const daiOut = new BN(await dai.balanceOf(to))
      // @ts-ignore
      expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
      // @ts-ignore
      expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
    })

    describe('with extra eDai reserves', () => {
      beforeEach(async () => {
        const additionalEDaiReserves = toWad(34.4)
        await eDai1.mint(operator, additionalEDaiReserves, { from: owner })
        await eDai1.approve(pool.address, additionalEDaiReserves, { from: operator })
        await pool.sellEDai(operator, operator, additionalEDaiReserves, { from: operator })
      })

      it('mints liquidity tokens with delegation', async () => {
        // Use this to test: https://www.desmos.com/calculator/mllhtohxfx

        const oneToken = toWad(1)
        await dai.mint(from, oneToken, { from: owner })
        await eDai1.mint(from, eDaiTokens1, { from: owner })

        const eDaiBefore = new BN(await eDai1.balanceOf(from))
        const poolTokensBefore = new BN(await pool.balanceOf(to))

        await dai.approve(pool.address, oneToken, { from: from })
        await eDai1.approve(pool.address, eDaiTokens1, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.mint(from, to, oneToken, { from: operator })

        const expectedMinted = new BN('1473236946700000000')
        const expectedEDaiIn = new BN('517558731280000000')

        const minted = new BN(await pool.balanceOf(to)).sub(poolTokensBefore)
        const eDaiIn = eDaiBefore.sub(new BN(await eDai1.balanceOf(from)))

        expect(minted).to.be.bignumber.gt(expectedMinted.mul(new BN('9999')).div(new BN('10000')))
        expect(minted).to.be.bignumber.lt(expectedMinted.mul(new BN('10001')).div(new BN('10000')))

        expect(eDaiIn).to.be.bignumber.gt(expectedEDaiIn.mul(new BN('9999')).div(new BN('10000')))
        expect(eDaiIn).to.be.bignumber.lt(expectedEDaiIn.mul(new BN('10001')).div(new BN('10000')))
      })

      it('burns liquidity tokens', async () => {
        // Use this to test: https://www.desmos.com/calculator/ubsalzunpo

        const oneToken = toWad(1)
        const eDaiReservesBefore = new BN(await eDai1.balanceOf(pool.address))
        const daiReservesBefore = new BN(await dai.balanceOf(pool.address))

        await pool.approve(pool.address, oneToken, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.burn(from, to, oneToken, { from: operator })

        const expectedEDaiOut = new BN('351307189540000000')
        const expectedDaiOut = new BN('678777437820000000')

        const eDaiOut = eDaiReservesBefore.sub(new BN(await eDai1.balanceOf(pool.address)))
        const daiOut = daiReservesBefore.sub(new BN(await dai.balanceOf(pool.address)))

        expect(eDaiOut).to.be.bignumber.gt(expectedEDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(eDaiOut).to.be.bignumber.lt(expectedEDaiOut.mul(new BN('10001')).div(new BN('10000')))

        expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
      })

      it('sells dai with delegation', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // eDaiOutForChaiIn formula: https://www.desmos.com/calculator/8eczy19er3

        assert.equal(
          await eDai1.balanceOf(to),
          0,
          "'To' wallet should have no eDai, instead has " + (await eDai1.balanceOf(operator))
        )

        await dai.approve(pool.address, oneToken, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.sellDai(from, to, oneToken, { from: operator })

        assert.equal(
          await dai.balanceOf(from),
          daiTokens1.sub(oneToken).toString(),
          "'From' wallet should have " + daiTokens1.sub(oneToken) + ' dai tokens'
        )

        const expectedEDaiOut = new BN(oneToken.toString()).mul(new BN('117440')).div(new BN('100000'))
        const eDaiOut = new BN(await eDai1.balanceOf(to))
        // This is the lowest precision achieved.
        // @ts-ignore
        expect(eDaiOut).to.be.bignumber.gt(expectedEDaiOut.mul(new BN('999')).div(new BN('1000')))
        // @ts-ignore
        expect(eDaiOut).to.be.bignumber.lt(expectedEDaiOut.mul(new BN('1001')).div(new BN('1000')))
      })

      it('buys eDai with delegation', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // chaiInForEDaiOut formula: https://www.desmos.com/calculator/grjod0grzp

        assert.equal(
          await eDai1.balanceOf(to),
          0,
          "'To' wallet should have no eDai, instead has " + (await eDai1.balanceOf(to))
        )

        await dai.approve(pool.address, daiTokens1, { from: from })
        await pool.addDelegate(operator, { from: from })
        await pool.buyEDai(from, to, oneToken, { from: operator })

        assert.equal(await eDai1.balanceOf(to), oneToken.toString(), "'To' wallet should have 1 eDai token")

        const expectedDaiIn = new BN(oneToken.toString()).mul(new BN('85110')).div(new BN('100000'))
        const daiIn = new BN(daiTokens1.toString()).sub(new BN(await dai.balanceOf(from)))
        // @ts-ignore
        expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')))
        // @ts-ignore
        expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')))
      })
    })
  })
})
