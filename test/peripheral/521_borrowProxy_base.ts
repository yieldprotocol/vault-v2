const Pool = artifacts.require('Pool')
const BorrowProxy = artifacts.require('BorrowProxy')

import { WETH, spot, wethTokens1, toWad, toRay, mulRay, bnify, MAX } from '../shared/utils'
import { MakerEnvironment, YieldEnvironmentLite, Contract } from '../shared/fixtures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'

// @ts-ignore
import { balance, BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('BorrowProxy', async (accounts) => {
  let [owner, user1, user2] = accounts

  let env: YieldEnvironmentLite
  let maker: MakerEnvironment
  let controller: Contract
  let treasury: Contract
  let weth: Contract
  let dai: Contract
  let vat: Contract
  let fyDai1: Contract
  let pool: Contract
  let proxy: Contract

  // These values impact the pool results
  const rate1 = toRay(1.02)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const fyDaiTokens1 = daiTokens1
  const oneToken = toWad(1)

  let maturity1: number

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    maker = env.maker
    weth = maker.weth
    dai = maker.dai
    vat = maker.vat
    controller = env.controller
    treasury = env.treasury
    fyDai1 = env.fyDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, fyDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup LimitPool
    proxy = await BorrowProxy.new(controller.address, { from: owner })

    // Allow owner to mint fyDai the sneaky way, without recording a debt in controller
    await fyDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
  })

  describe('collateral', () => {
    it('allows user to post eth', async () => {
      assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury has weth in MakerDAO')
      assert.equal(await controller.powerOf(WETH, user2), 0, 'User2 has borrowing power')

      const previousBalance = await balance.current(user1)
      await proxy.post(user2, { from: user1, value: wethTokens1 })

      expect(await balance.current(user1)).to.be.bignumber.lt(previousBalance)
      assert.equal((await vat.urns(WETH, treasury.address)).ink, wethTokens1, 'Treasury should have weth in MakerDAO')
      assert.equal(
        await controller.powerOf(WETH, user2),
        mulRay(wethTokens1, spot).toString(),
        'User2 should have ' +
          mulRay(wethTokens1, spot) +
          ' borrowing power, instead has ' +
          (await controller.powerOf(WETH, user2))
      )
    })

    describe('with posted eth', () => {
      beforeEach(async () => {
        await proxy.post(user1, { from: user1, value: wethTokens1 })

        assert.equal(
          (await vat.urns(WETH, treasury.address)).ink,
          wethTokens1,
          'Treasury does not have weth in MakerDAO'
        )
        assert.equal(
          await controller.powerOf(WETH, user1),
          mulRay(wethTokens1, spot).toString(),
          'User1 does not have borrowing power'
        )
        assert.equal(await weth.balanceOf(user2), 0, 'User2 has collateral in hand')
      })

      it('checks missing approvals and signatures for withdrawing', async () => {
        let result = await proxy.withdrawCheck({ from: user2 })

        assert.equal(result[0], true)
        assert.equal(result[1], false)

        await controller.addDelegate(proxy.address, { from: user2 })
        result = await proxy.withdrawCheck({ from: user2 })

        assert.equal(result[0], true)
        assert.equal(result[1], true)
      })

      it('allows user to withdraw weth', async () => {
        await controller.addDelegate(proxy.address, { from: user1 })
        const previousBalance = await balance.current(user2)
        await proxy.withdraw(user2, wethTokens1, { from: user1 })

        expect(await balance.current(user2)).to.be.bignumber.gt(previousBalance)
        assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury should not not have weth in MakerDAO')
        assert.equal(await controller.powerOf(WETH, user1), 0, 'User1 should not have borrowing power')
      })
    })

    describe('borrowing', () => {
      beforeEach(async () => {
        // Init pool
        const daiReserves = daiTokens1
        await env.maker.getDai(user1, daiReserves, rate1)
        await dai.approve(pool.address, MAX, { from: user1 })
        await fyDai1.approve(pool.address, MAX, { from: user1 })
        await pool.mint(user1, user1, daiReserves, { from: user1 })

        // Post some weth to controller via the proxy to be able to borrow
        // without requiring an `approve`!
        await proxy.post(user1, { from: user1, value: bnify(wethTokens1).mul(2).toString() })

        // Give some fyDai to user1
        await fyDai1.mint(user1, fyDaiTokens1, { from: owner })

        await pool.sellFYDai(user1, user1, fyDaiTokens1.div(10), { from: user1 })
      })

      it('checks missing approvals and signatures for borrowing', async () => {
        let result = await proxy.borrowDaiForMaximumFYDaiCheck(pool.address, { from: user1 })

        assert.equal(result[0], false)
        assert.equal(result[1], false)

        await controller.addDelegate(proxy.address, { from: user1 })
        result = await proxy.borrowDaiForMaximumFYDaiCheck(pool.address, { from: user1 })

        assert.equal(result[0], false)
        assert.equal(result[1], true)

        await proxy.borrowDaiForMaximumFYDaiWithSignature(
          pool.address,
          WETH,
          maturity1,
          user2,
          fyDaiTokens1,
          oneToken,
          '0x',
          {
            from: user1,
          }
        )
        result = await proxy.borrowDaiForMaximumFYDaiCheck(pool.address, { from: user1 })

        assert.equal(result[0], true)
        assert.equal(result[1], true)
      })

      it('borrows dai for maximum fyDai', async () => {
        await controller.addDelegate(proxy.address, { from: user1 })
        await proxy.borrowDaiForMaximumFYDaiWithSignature(
          pool.address,
          WETH,
          maturity1,
          user2,
          fyDaiTokens1,
          oneToken,
          '0x',
          {
            from: user1,
          }
        )

        assert.equal(await dai.balanceOf(user2), oneToken.toString())
      })

      it("doesn't borrow dai if limit exceeded", async () => {
        await controller.addDelegate(proxy.address, { from: user1 })
        await expectRevert(
          proxy.borrowDaiForMaximumFYDai(pool.address, WETH, maturity1, user2, 0, oneToken, {
            from: user1,
          }),
          'BorrowProxy: Too much fyDai required'
        )
      })

      describe('once borrowed', () => {
        beforeEach(async () => {
          await controller.addDelegate(proxy.address, { from: user1 })
          await proxy.borrowDaiForMaximumFYDaiWithSignature(
            pool.address,
            WETH,
            maturity1,
            user2,
            fyDaiTokens1,
            oneToken.mul(2),
            '0x',
            {
              from: user1,
            }
          )
        })

        it('approvals only need to be set up once', async () => {
          await proxy.borrowDaiForMaximumFYDai(pool.address, WETH, maturity1, user2, fyDaiTokens1, oneToken, {
            from: user1,
          })
        })

        it('checks missing approvals and signatures for repaying', async () => {
          await controller.revokeDelegate(proxy.address, { from: user1 })
          let result = await proxy.repayDaiCheck({ from: user1 })

          assert.equal(result[0], true)
          assert.equal(result[1], false)
          assert.equal(result[2], false)

          await dai.approve(treasury.address, MAX, { from: user1 })
          result = await proxy.repayDaiCheck({ from: user1 })

          assert.equal(result[0], true)
          assert.equal(result[1], true)
          assert.equal(result[2], false)

          await controller.addDelegate(proxy.address, { from: user1 })
          result = await proxy.repayDaiCheck({ from: user1 })

          assert.equal(result[0], true)
          assert.equal(result[1], true)
          assert.equal(result[2], true)
        })

        it('repays debt', async () => {
          await env.maker.getDai(user1, oneToken, rate1)
          await dai.approve(treasury.address, MAX, { from: user1 })
          const debtBefore = await controller.debtDai(WETH, maturity1, user1)
          await proxy.repayDaiWithSignature(WETH, maturity1, user1, oneToken, '0x', '0x', {
            from: user1,
          })
          const debtAfter = await controller.debtDai(WETH, maturity1, user1)
          expect(debtAfter.toString()).to.be.bignumber.eq(debtBefore.sub(new BN(oneToken.toString())).toString())
        })

        it.only('checks missing approvals and signatures for repaying at pool rates', async () => {
          await controller.revokeDelegate(proxy.address, { from: user1 })
          let result = await proxy.repayMinimumFYDaiDebtForDaiCheck(pool.address, { from: user1 })

          assert.equal(result[0], false)
          assert.equal(result[1], false)
          assert.equal(result[2], false)

          await proxy.repayMinimumFYDaiDebtForDaiApprove(pool.address, { from: user1 })
          result = await proxy.repayMinimumFYDaiDebtForDaiCheck(pool.address, { from: user1 })

          assert.equal(result[0], true)
          assert.equal(result[1], false)
          assert.equal(result[2], false)

          await controller.addDelegate(proxy.address, { from: user1 })
          result = await proxy.repayMinimumFYDaiDebtForDaiCheck(pool.address, { from: user1 })

          assert.equal(result[0], true)
          assert.equal(result[1], true)
          assert.equal(result[2], false)

          await pool.addDelegate(proxy.address, { from: user1 })
          result = await proxy.repayMinimumFYDaiDebtForDaiCheck(pool.address, { from: user1 })

          assert.equal(result[0], true)
          assert.equal(result[1], true)
          assert.equal(result[2], true)
        })

        it('repays debt at pool rates', async () => {
          await env.maker.getDai(user1, oneToken, rate1)

          const debtBefore = await controller.debtFYDai(WETH, maturity1, user1)
          const paidDebt = await pool.sellDaiPreview(oneToken)

          // await controller.addDelegate(proxy.address, { from: user1 })
          await pool.addDelegate(proxy.address, { from: user1 })
          await proxy.repayMinimumFYDaiDebtForDaiWithSignature(pool.address, WETH, maturity1, user1, 0, oneToken, '0x', '0x', {
            from: user1,
          })
          const debtAfter = await controller.debtFYDai(WETH, maturity1, user1)
          // Prices slip each block
          expect(debtAfter.toString()).to.be.bignumber.gt(debtBefore.sub(paidDebt).toString())
          expect(debtAfter.toString()).to.be.bignumber.lt(
            debtBefore.sub(paidDebt).mul(new BN('100000')).div(new BN('99999')).toString()
          )
        })

        it('repays debt at pool rates, but takes only as much Dai as needed', async () => {
          await env.maker.getDai(user1, oneToken, rate1)

          const debtFYDai = await controller.debtFYDai(WETH, maturity1, user1)
          const debtDaiValue = await pool.buyFYDaiPreview(debtFYDai)
          const daiBalanceBefore = await dai.balanceOf(user1)

          // await controller.addDelegate(proxy.address, { from: user1 })
          await pool.addDelegate(proxy.address, { from: user1 })
          await proxy.repayMinimumFYDaiDebtForDaiWithSignature(pool.address, WETH, maturity1, user1, 0, oneToken.mul(3), '0x', '0x', {
            from: user1,
          })
          const debtAfter = await controller.debtFYDai(WETH, maturity1, user1)
          const daiBalanceAfter = await dai.balanceOf(user1)
          assert.equal(debtAfter, 0)
          // Prices slip each block
          expect(daiBalanceAfter.toString()).to.be.bignumber.lt(daiBalanceBefore.sub(debtDaiValue).toString())
          expect(daiBalanceAfter.toString()).to.be.bignumber.gt(
            daiBalanceBefore.sub(debtDaiValue).mul(new BN('99999')).div(new BN('100000')).toString()
          )
        })

        it('repays debt at pool rates, if enough can be repaid with the Dai provided', async () => {
          await env.maker.getDai(user1, oneToken, rate1)
          // await dai.approve(treasury.address, MAX, { from: user1 })

          // await controller.addDelegate(proxy.address, { from: user1 })
          await pool.addDelegate(proxy.address, { from: user1 })
          await expectRevert(
            proxy.repayMinimumFYDaiDebtForDaiWithSignature(pool.address, WETH, maturity1, user1, MAX, oneToken, '0x', '0x', {
              from: user1,
            }),
            'BorrowProxy: Not enough fyDai debt repaid'
          )
        })
      })
    })
  })

  describe('lend', () => {
    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(owner, daiReserves, rate1)

      await fyDai1.approve(pool.address, -1, { from: owner })
      await dai.approve(pool.address, -1, { from: owner })
      await pool.mint(owner, owner, daiReserves, { from: owner })

      await fyDai1.approve(pool.address, -1, { from: user1 })
      await dai.approve(pool.address, -1, { from: user1 })
      await pool.addDelegate(proxy.address, { from: user1 })
    })

    it('checks missing approvals and signatures for selling fyDai', async () => {
      let result = await proxy.sellFYDaiCheck(pool.address, { from: user2 })

      assert.equal(result[0], true)
      assert.equal(result[1], false)
      assert.equal(result[2], false)

      await fyDai1.approve(pool.address, MAX, { from: user2 })
      result = await proxy.sellFYDaiCheck(pool.address, { from: user2 })

      assert.equal(result[0], true)
      assert.equal(result[1], true)
      assert.equal(result[2], false)

      await pool.addDelegate(proxy.address, { from: user2 })
      result = await proxy.sellFYDaiCheck(pool.address, { from: user2 })

      assert.equal(result[0], true)
      assert.equal(result[1], true)
      assert.equal(result[2], true)
    })

    it('sells fyDai', async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(user1, oneToken, { from: owner })

      await proxy.sellFYDai(pool.address, user2, oneToken, oneToken.div(2), { from: user1 })

      assert.equal(await fyDai1.balanceOf(user1), 0, "'From' wallet should have no fyDai tokens")

      const expectedDaiOut = new BN(oneToken.toString()).mul(new BN('99732')).div(new BN('100000'))
      const daiOut = new BN(await dai.balanceOf(user2))
      expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
    })

    it("doesn't sell fyDai if limit not reached", async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(user1, oneToken, { from: owner })

      await expectRevert(
        proxy.sellFYDai(pool.address, user2, oneToken, oneToken.mul(2), { from: user1 }),
        'BorrowProxy: Limit not reached'
      )
    })

    it("doesn't sell fyDai if limit not reached", async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(user1, oneToken, { from: owner })

      await expectRevert(
        proxy.sellFYDai(pool.address, user2, oneToken, oneToken.mul(2), { from: user1 }),
        'BorrowProxy: Limit not reached'
      )
    })

    it('buys dai', async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(user1, oneToken.mul(2), { from: owner })

      await proxy.buyDai(pool.address, user2, oneToken, oneToken.mul(2), { from: user1 })

      assert.equal((await dai.balanceOf(user2)).toString(), oneToken.toString(), 'User2 should have received one Dai')
    })

    it("doesn't buy dai if limit exceeded", async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(user1, oneToken.mul(2), { from: owner })

      await expectRevert(
        proxy.buyDai(pool.address, user2, oneToken, oneToken.div(2), { from: user1 }),
        'BorrowProxy: Limit exceeded'
      )
    })

    describe('with extra fyDai reserves', () => {
      beforeEach(async () => {
        const additionalFYDaiReserves = toWad(34.4)
        await fyDai1.mint(owner, additionalFYDaiReserves, { from: owner })
        await fyDai1.approve(pool.address, additionalFYDaiReserves, { from: owner })
        await pool.sellFYDai(owner, owner, additionalFYDaiReserves, { from: owner })

        await env.maker.getDai(user1, daiTokens1, rate1)
      })

      it('checks missing approvals and signatures for selling dai', async () => {
        let result = await proxy.sellDaiCheck(pool.address, { from: user2 })

        assert.equal(result[0], true)
        assert.equal(result[1], false)
        assert.equal(result[2], false)

        await dai.approve(pool.address, MAX, { from: user2 })
        result = await proxy.sellDaiCheck(pool.address, { from: user2 })

        assert.equal(result[0], true)
        assert.equal(result[1], true)
        assert.equal(result[2], false)

        await pool.addDelegate(proxy.address, { from: user2 })
        result = await proxy.sellDaiCheck(pool.address, { from: user2 })

        assert.equal(result[0], true)
        assert.equal(result[1], true)
        assert.equal(result[2], true)
      })

      it('sells dai', async () => {
        const oneToken = toWad(1)
        const daiBalance = await dai.balanceOf(user1)

        // fyDaiOutForDaiIn formula: https://www.desmos.com/calculator/8eczy19er3

        await proxy.sellDai(pool.address, user2, oneToken, oneToken.div(2), { from: user1 })

        const expectedFYDaiOut = new BN(oneToken.toString()).mul(new BN('117440')).div(new BN('100000'))
        const fyDaiOut = new BN(await fyDai1.balanceOf(user2))

        assert.equal(
          await dai.balanceOf(user1),
          daiBalance.sub(new BN(oneToken.toString())).toString(),
          'User1 should have ' + daiTokens1.sub(oneToken) + ' dai tokens'
        )

        expect(fyDaiOut).to.be.bignumber.gt(expectedFYDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(fyDaiOut).to.be.bignumber.lt(expectedFYDaiOut.mul(new BN('10001')).div(new BN('10000')))
      })

      it("doesn't sell dai if minimum not reached", async () => {
        await expectRevert(
          proxy.sellDai(pool.address, user2, oneToken, oneToken.mul(2), { from: user1 }),
          'BorrowProxy: Limit not reached'
        )
      })
    })
  })
})
