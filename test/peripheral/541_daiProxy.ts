const Pool = artifacts.require('Pool')
const DaiProxy = artifacts.require('DaiProxy')

import { WETH, wethTokens1, toWad, toRay, subBN, mulRay } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('DaiProxy', async (accounts) => {
  let [owner, user1, user2, operator] = accounts

  // These values impact the pool results
  const rate1 = toRay(1.4)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const yDaiTokens1 = daiTokens1

  let maturity1: number
  let vat: Contract
  let pot: Contract
  let weth: Contract
  let dai: Contract
  let treasury: Contract
  let controller: Contract
  let yDai1: Contract
  let pool: Contract
  let daiProxy: Contract
  let env: YieldEnvironmentLite

  beforeEach(async () => {
    env = await YieldEnvironmentLite.setup()
    vat = env.maker.vat
    weth = env.maker.weth
    dai = env.maker.dai
    pot = env.maker.pot
    treasury = env.treasury
    controller = env.controller

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    yDai1 = await env.newYDai(maturity1, 'Name', 'Symbol')

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup DaiProxy
    daiProxy = await DaiProxy.new(vat.address, dai.address, pot.address, controller.address, pool.address, {
      from: owner,
    })

    // Test setup

    // Allow owner to mint yDai the sneaky way, without recording a debt in controller
    await yDai1.orchestrate(owner, { from: owner })
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      // Init pool
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)
      await dai.approve(pool.address, daiReserves, { from: user1 })
      await pool.init(daiReserves, { from: user1 })

      // Allow daiProxy to act for `user1`
      await pool.addDelegate(daiProxy.address, { from: user1 })
      await controller.addDelegate(daiProxy.address, { from: user1 })

      // Post some weth to controller to be able to borrow
      await weth.deposit({ from: user1, value: wethTokens1 })
      await weth.approve(treasury.address, wethTokens1, { from: user1 })
      await controller.post(WETH, user1, user1, wethTokens1, { from: user1 })

      // Give some yDai to user1
      await yDai1.mint(user1, yDaiTokens1, { from: owner })
    })

    it('borrows dai for maximum yDai', async () => {
      const oneToken = toWad(1)

      await daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, user2, yDaiTokens1, oneToken, { from: user1 })

      assert.equal(await dai.balanceOf(user2), oneToken.toString())
    })

    it("doesn't borrow dai if limit exceeded", async () => {
      await expectRevert(
        daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, user2, yDaiTokens1, daiTokens1, { from: user1 }),
        'DaiProxy: Too much yDai required'
      )
    })

    it('borrows minimum dai for yDai', async () => {
      const oneToken = new BN(toWad(1).toString())

      await daiProxy.borrowMinimumDaiForYDai(WETH, maturity1, user2, yDaiTokens1, oneToken, { from: user1 })

      expect(await dai.balanceOf(user2)).to.be.bignumber.gt(oneToken)
      assert.equal(await yDai1.balanceOf(user1), subBN(yDaiTokens1, oneToken).toString())
    })

    it("doesn't borrow dai if limit not reached", async () => {
      const oneToken = new BN(toWad(1).toString())

      await expectRevert(
        daiProxy.borrowMinimumDaiForYDai(WETH, maturity1, user2, oneToken, daiTokens1, { from: user1 }),
        'DaiProxy: Not enough Dai obtained'
      )
    })

    describe('with extra yDai reserves', () => {
      beforeEach(async () => {
        // Set up the pool to allow buying yDai
        const additionalYDaiReserves = toWad(34.4)
        await yDai1.mint(operator, additionalYDaiReserves, { from: owner })
        await yDai1.approve(pool.address, additionalYDaiReserves, { from: operator })
        await pool.sellYDai(operator, operator, additionalYDaiReserves, { from: operator })

        // Create some yDai debt for `user2`
        await weth.deposit({ from: user2, value: wethTokens1 })
        await weth.approve(treasury.address, wethTokens1, { from: user2 })
        await controller.post(WETH, user2, user2, wethTokens1, { from: user2 })
        await controller.borrow(WETH, maturity1, user2, user2, daiTokens1, { from: user2 })

        // Give some Dai to `user1`
        await env.maker.getDai(user1, daiTokens1, rate1)
      })

      it('repays minimum yDai debt with dai', async () => {
        const oneYDai = toWad(1)
        const twoDai = toWad(2)
        const yDaiDebt = new BN(daiTokens1.toString())

        await dai.approve(pool.address, daiTokens1, { from: user1 })
        await daiProxy.repayMinimumYDaiDebtForDai(WETH, maturity1, user2, oneYDai, twoDai, { from: user1 })

        expect(await controller.debtYDai(WETH, maturity1, user2)).to.be.bignumber.lt(yDaiDebt)
        assert.equal(await dai.balanceOf(user1), subBN(daiTokens1, twoDai).toString())
      })

      it("doesn't repay debt if limit not reached", async () => {
        const oneDai = toWad(1)
        const twoYDai = toWad(2)

        await dai.approve(pool.address, daiTokens1, { from: user1 })

        await expectRevert(
          daiProxy.repayMinimumYDaiDebtForDai(WETH, maturity1, user2, twoYDai, oneDai, { from: user1 }),
          'DaiProxy: Not enough yDai debt repaid'
        )
      })

      it('repays yDai debt with maximum dai', async () => {
        const oneYDai = toWad(1)
        const twoDai = toWad(2)
        const yDaiDebt = daiTokens1

        await dai.approve(pool.address, daiTokens1, { from: user1 })
        await daiProxy.repayYDaiDebtForMaximumDai(WETH, maturity1, user2, oneYDai, twoDai, { from: user1 })

        expect(await dai.balanceOf(user1)).to.be.bignumber.lt(new BN(daiTokens1.toString()))
        assert.equal(await controller.debtYDai(WETH, maturity1, user2), subBN(yDaiDebt, oneYDai).toString())
      })

      it("doesn't repay debt if limit not reached", async () => {
        const oneDai = toWad(1)
        const twoYDai = toWad(2)

        await dai.approve(pool.address, daiTokens1, { from: user1 })

        await expectRevert(
          daiProxy.repayYDaiDebtForMaximumDai(WETH, maturity1, user2, twoYDai, oneDai, { from: user1 }),
          'DaiProxy: Too much Dai required'
        )
      })
    })
  })
})
