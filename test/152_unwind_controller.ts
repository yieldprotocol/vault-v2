import { id } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
import { BigNumber } from 'ethers'
// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import {
  CHAI,
  WETH,
  spot,
  rate1,
  chi1,
  daiTokens1,
  wethTokens1,
  chaiTokens1,
  toRay,
  mulRay,
  divRay,
} from './shared/utils'
import { YieldEnvironment, Contract } from './shared/fixtures'

contract('Unwind - Controller', async (accounts) => {
  let [owner, user1, user2, user3] = accounts

  let snapshot: any
  let snapshotId: string

  let env: YieldEnvironment

  let controller: Contract
  let treasury: Contract
  let yDai1: Contract
  let yDai2: Contract
  let weth: Contract
  let unwind: Contract
  let end: Contract

  let maturity1: number
  let maturity2: number

  const fix = divRay(toRay(1.0), mulRay(spot, toRay(1.1)))
  const fixedWeth = mulRay(daiTokens1, fix)
  const yDaiTokens = daiTokens1

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000
    maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000

    env = await YieldEnvironment.setup([maturity1, maturity2])
    controller = env.controller
    treasury = env.treasury
    unwind = env.unwind
    yDai1 = env.yDais[0]
    yDai2 = env.yDais[1]

    weth = env.maker.weth
    end = env.maker.end

    await end.rely(owner, { from: owner }) // `owner` replaces MKR governance
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  describe('with posted collateral and borrowed yDai', () => {
    beforeEach(async () => {
      // Weth setup
      await env.postWeth(user1, wethTokens1)

      await env.postWeth(user2, BigNumber.from(wethTokens1).add(1))
      await controller.borrow(WETH, maturity1, user2, user2, daiTokens1, { from: user2 })

      await env.postWeth(user3, BigNumber.from(wethTokens1).mul(3))
      await controller.borrow(WETH, maturity1, user3, user3, daiTokens1, { from: user3 })
      await controller.borrow(WETH, maturity2, user3, user3, daiTokens1, { from: user3 })

      await env.postChai(user1, chaiTokens1, chi1, rate1)

      const moreChai = mulRay(chaiTokens1, toRay(1.1))
      await env.postChai(user2, moreChai, chi1, rate1)
      await controller.borrow(CHAI, maturity1, user2, user2, daiTokens1, { from: user2 })

      // Make sure that end.sol will have enough weth to cash chai savings
      await env.maker.getDai(owner, BigNumber.from(wethTokens1).mul(10), rate1)

      assert.equal(await weth.balanceOf(user1), 0, 'User1 should have no weth')
      assert.equal(await weth.balanceOf(user2), 0, 'User2 should have no weth')
      assert.equal(
        await controller.debtYDai(WETH, maturity1, user2),
        yDaiTokens.toString(),
        'User2 should have ' +
          yDaiTokens.toString() +
          ' maturity1 weth debt, instead has ' +
          (await controller.debtYDai(WETH, maturity1, user2)).toString()
      )
    })

    it('does not allow to redeem YDai if treasury not settled and cashed', async () => {
      await expectRevert(unwind.redeem(maturity1, user2, { from: user2 }), 'Unwind: Not ready')
    })

    it('does not allow to settle users if treasury not settled and cashed', async () => {
      await expectRevert(unwind.settle(WETH, user2, { from: user2 }), 'Unwind: Not ready')
    })

    describe('with Dss unwind initiated and treasury settled', () => {
      beforeEach(async () => {
        await env.shutdown(owner, user1, user2)
      })

      it('controller shuts down', async () => {
        assert.equal(await controller.live(), false, 'Controller should not be live')
      })

      it('does not allow to post, withdraw, borrow or repay assets', async () => {
        await expectRevert(
          controller.post(WETH, owner, owner, wethTokens1, { from: owner }),
          'Controller: Not available during unwind'
        )
        await expectRevert(
          controller.withdraw(WETH, owner, owner, wethTokens1, { from: owner }),
          'Controller: Not available during unwind'
        )
        await expectRevert(
          controller.borrow(WETH, maturity1, owner, owner, yDaiTokens, { from: owner }),
          'Controller: Not available during unwind'
        )
        await expectRevert(
          controller.repayDai(WETH, maturity1, owner, owner, daiTokens1, { from: owner }),
          'Controller: Not available during unwind'
        )
        await expectRevert(
          controller.repayYDai(WETH, maturity1, owner, owner, yDaiTokens, { from: owner }),
          'Controller: Not available during unwind'
        )
      })

      it('user can redeem YDai', async () => {
        assert.equal(
          await yDai1.balanceOf(user2),
          yDaiTokens.mul(2).toString(),
          'User2 should have ' + yDaiTokens.mul(2) + ' yDai, instead has ' + (await yDai1.balanceOf(user2)).toString()
        )
        await unwind.redeem(maturity1, user2, { from: user2 })

        assert.equal(
          await weth.balanceOf(user2),
          fixedWeth.mul(2).add(1).toString(),
          'User2 should have ' +
            fixedWeth.mul(2).add(1).toString() +
            ' weth wei, instead has ' +
            (await weth.balanceOf(user2)).toString()
        )
      })

      it('allows user to settle weth surplus', async () => {
        await unwind.settle(WETH, user1, { from: user1 })

        assert.equal(
          await weth.balanceOf(user1),
          wethTokens1.toString(),
          'User1 should have ' + wethTokens1.toString() + ' weth wei'
        )
      })

      it('users can be forced to settle weth surplus', async () => {
        await unwind.settle(WETH, user1, { from: owner })

        assert.equal(
          await weth.balanceOf(user1),
          wethTokens1.toString(),
          'User1 should have ' + wethTokens1.toString() + ' weth wei'
        )
      })

      it('allows user to settle chai surplus', async () => {
        await unwind.settle(CHAI, user1, { from: user1 })

        // Remember that chai is converted to weth when withdrawing
        assert.equal(
          await weth.balanceOf(user1),
          fixedWeth.toString(),
          'User1 should have ' + fixedWeth.sub(1).toString() + ' weth wei'
        )
      })

      it('users can be forced to settle chai surplus', async () => {
        await unwind.settle(CHAI, user1, { from: owner })

        // Remember that chai is converted to weth when withdrawing
        assert.equal(
          await weth.balanceOf(user1),
          fixedWeth.toString(),
          'User1 should have ' + fixedWeth.sub(1).toString() + ' weth wei'
        )
      })

      it('allows user to settle weth debt', async () => {
        await unwind.settle(WETH, user2, { from: user2 })

        assert.equal(await controller.debtYDai(WETH, maturity1, user2), 0, 'User2 should have no maturity1 weth debt')
        // In the tests the settling nets zero surplus, which we tested above
      })

      it('allows user to settle chai debt', async () => {
        await unwind.settle(CHAI, user2, { from: user2 })

        assert.equal(await controller.debtYDai(CHAI, maturity1, user2), 0, 'User2 should have no maturity1 chai debt')
        // In the tests the settling nets zero surplus, which we tested above
      })

      it('allows user to settle mutiple weth positions', async () => {
        await unwind.settle(WETH, user3, { from: user3 })

        assert.equal(
          await weth.balanceOf(user3),
          BigNumber.from(wethTokens1).mul(3).sub(fixedWeth.mul(2)).sub(1).toString(), // Each position settled substracts daiTokens1 * fix from the user collateral
          'User1 should have ' +
            BigNumber.from(wethTokens1).mul(3).sub(fixedWeth.mul(2)).sub(1).toString() +
            ' weth wei, instead has ' +
            (await weth.balanceOf(user3))
        )
        // In the tests the settling nets zero surplus, which we tested above
      })
    })
  })
})
