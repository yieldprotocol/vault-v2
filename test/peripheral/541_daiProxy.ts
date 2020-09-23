const Pool = artifacts.require('Pool')
const DaiProxy = artifacts.require('YieldProxy')

import { WETH, rate1, daiTokens1, wethTokens1, toWad, subBN, bnify, MAX, chainId, name, ZERO } from '../shared/utils'
import { MakerEnvironment, YieldEnvironmentLite, Contract } from '../shared/fixtures'
import { getSignatureDigest, getPermitDigest, getDaiDigest, userPrivateKey, sign } from '../shared/signatures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('YieldProxy - DaiProxy', async (accounts) => {
  let [owner, user1, user2, operator] = accounts

  let maturity1: number
  let dai: Contract
  let controller: Contract
  let eDai1: Contract
  let pool: Contract
  let daiProxy: Contract
  let maker: MakerEnvironment
  let env: YieldEnvironmentLite

  const one = toWad(1)
  const two = toWad(2)
  const eDaiTokens1 = daiTokens1
  const eDaiDebt = daiTokens1

  let digest: any

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    maker = env.maker
    dai = env.maker.dai
    controller = env.controller

    eDai1 = env.eDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, eDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup DaiProxy
    daiProxy = await DaiProxy.new(env.controller.address, [pool.address])

    // Allow owner to mint eDai the sneaky way, without recording a debt in controller
    await eDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })

    const deadline = MAX

    // Authorize the proxy for the controller
    digest = getSignatureDigest(
      name,
      controller.address,
      chainId,
      {
        user: user1,
        delegate: daiProxy.address,
      },
      await controller.signatureCount(user1),
      MAX
    )
    const controllerSig = sign(digest, userPrivateKey)

    // Authorize DAI
    digest = getDaiDigest(
      await dai.name(),
      dai.address,
      chainId,
      {
        owner: user1,
        spender: daiProxy.address,
        can: true,
      },
      bnify(await dai.nonces(user1)),
      deadline
    )
    let daiSig = sign(digest, userPrivateKey)

    // Send it! (note how it's not necessarily the user broadcasting it)
    await daiProxy.onboard(user1, daiSig, controllerSig, { from: operator })

    // Authorize the proxy for the pool
    digest = getSignatureDigest(
      name,
      pool.address,
      chainId,
      {
        user: user1,
        delegate: daiProxy.address,
      },
      bnify(await pool.signatureCount(user1)),
      MAX
    )
    const poolSig = sign(digest, userPrivateKey)

    // Authorize EDai for the pool
    digest = getPermitDigest(
      await eDai1.name(),
      await pool.eDai(),
      chainId,
      {
        owner: user1,
        spender: daiProxy.address,
        value: MAX,
      },
      bnify(await eDai1.nonces(user1)),
      MAX
    )
    const eDaiSig = sign(digest, userPrivateKey)

    // Authorize DAI for the pool
    digest = getDaiDigest(
      await dai.name(),
      dai.address,
      chainId,
      {
        owner: user1,
        spender: pool.address,
        can: true,
      },
      bnify(await dai.nonces(user1)),
      deadline
    )
    const daiSig2 = sign(digest, userPrivateKey)
    // Send it!
    await daiProxy.authorizePool(pool.address, user1, daiSig2, eDaiSig, poolSig, { from: operator })
  })

  describe('on controller', () => {
    beforeEach(async () => {
      // Get some debt
      await env.postWeth(user1, wethTokens1)
      const toBorrow = (await env.unlockedOf(WETH, user1)).toString()
      await controller.borrow(WETH, maturity1, user1, user1, toBorrow, { from: user1 })
    })

    it('repays debt with Dai and with signature', async () => {
      await maker.getDai(user1, daiTokens1, rate1)
      const debt = (await controller.debtDai(WETH, maturity1, user1)).toString()

      const deadline = MAX
      // Authorize DAI
      digest = getDaiDigest(
        await dai.name(),
        dai.address,
        chainId,
        {
          owner: user1,
          spender: env.treasury.address,
          can: true,
        },
        bnify(await dai.nonces(user1)),
        deadline
      )
      let daiSig = sign(digest, userPrivateKey)

      await daiProxy.repayDaiWithSignature(WETH, maturity1, user1, debt, daiSig, { from: user1 })
      assert.equal((await controller.debtDai(WETH, maturity1, user1)).toString(), ZERO)
    })
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      // Init pool
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)
      await dai.approve(pool.address, MAX, { from: user1 })
      await eDai1.approve(pool.address, MAX, { from: user1 })
      await pool.init(daiReserves, { from: user1 })

      // Post some weth to controller via the proxy to be able to borrow
      // without requiring an `approve`!
      await daiProxy.post(user1, { from: user1, value: bnify(wethTokens1).mul(2).toString() })

      // Give some eDai to user1
      await eDai1.mint(user1, eDaiTokens1, { from: owner })
    })

    it('fails on unknown pools', async () => {
      const fakePoolContract = await Pool.new(dai.address, eDai1.address, 'Fake', 'Fake')
      const fakePool = fakePoolContract.address

      await expectRevert(daiProxy.addLiquidity(fakePool, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.removeLiquidityEarlyDaiPool(fakePool, 1, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.removeLiquidityEarlyDaiFixed(fakePool, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.removeLiquidityMature(fakePool, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.borrowDaiForMaximumEDai(fakePool, WETH, 1, owner, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.borrowMinimumDaiForEDai(fakePool, WETH, 1, owner, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(
        daiProxy.repayMinimumEDaiDebtForDai(fakePool, WETH, 1, owner, 1, 1),
        'YieldProxy: Unknown pool'
      )
      await expectRevert(
        daiProxy.repayEDaiDebtForMaximumDai(fakePool, WETH, 1, owner, 1, 1),
        'YieldProxy: Unknown pool'
      )
    })

    it('borrows dai for maximum eDai', async () => {
      await daiProxy.borrowDaiForMaximumEDai(pool.address, WETH, maturity1, user2, eDaiTokens1, one, {
        from: user1,
      })

      assert.equal(await dai.balanceOf(user2), one.toString())
    })

    it("doesn't borrow dai if limit exceeded", async () => {
      await expectRevert(
        daiProxy.borrowDaiForMaximumEDai(pool.address, WETH, maturity1, user2, eDaiTokens1, daiTokens1, {
          from: user1,
        }),
        'YieldProxy: Too much eDai required'
      )
    })

    it('borrows minimum dai for eDai', async () => {
      const balanceBefore = bnify(await eDai1.balanceOf(user1))
      const balanceBefore2 = bnify(await dai.balanceOf(user2))
      await daiProxy.borrowMinimumDaiForEDai(pool.address, WETH, maturity1, user2, eDaiTokens1, one, {
        from: user1,
      })
      const balanceAfter = bnify(await eDai1.balanceOf(user1))
      const balanceAfter2 = bnify(await dai.balanceOf(user2))

      // user1's balance remains the same
      expect(balanceAfter.eq(balanceBefore)).to.be.true

      // user2 got >1 DAI
      expect(balanceAfter2.gt(balanceBefore2.add(one))).to.be.true
    })

    it("doesn't borrow dai if limit not reached", async () => {
      await expectRevert(
        daiProxy.borrowMinimumDaiForEDai(pool.address, WETH, maturity1, user2, one, daiTokens1, { from: user1 }),
        'YieldProxy: Not enough Dai obtained'
      )
    })

    describe('with extra eDai reserves', () => {
      beforeEach(async () => {
        // Set up the pool to allow buying eDai
        const additionalEDaiReserves = toWad(34.4)
        await eDai1.mint(operator, additionalEDaiReserves, { from: owner })
        await eDai1.approve(pool.address, additionalEDaiReserves, { from: operator })
        await pool.sellEDai(operator, operator, additionalEDaiReserves, { from: operator })

        // Create some eDai debt for `user1`
        await daiProxy.post(user1, { from: user1, value: bnify(wethTokens1).mul(2).toString() })
        await controller.borrow(WETH, maturity1, user1, user1, one, { from: user1 })

        // Create some eDai debt for `user2`
        await daiProxy.post(user2, { from: user2, value: bnify(wethTokens1).mul(2).toString() })
        await controller.borrow(WETH, maturity1, user2, user2, daiTokens1, { from: user2 })

        // Give some Dai to `user1`
        await env.maker.getDai(user1, bnify(daiTokens1).mul(2).toString(), rate1)
      })

      it('repays minimum eDai debt with dai', async () => {
        const user2DebtBefore = (await controller.debtEDai(WETH, maturity1, user2)).toString()
        const user1DaiBefore = (await dai.balanceOf(user1)).toString()

        await daiProxy.repayMinimumEDaiDebtForDai(pool.address, WETH, maturity1, user2, one, two, {
          from: user1,
        })

        const user2DebtAfter = (await controller.debtEDai(WETH, maturity1, user2)).toString()
        const user1DaiAfter = (await dai.balanceOf(user1)).toString()

        expect(bnify(user2DebtAfter).lt(bnify(user2DebtBefore))).to.be.true
        assert.equal(user1DaiAfter, subBN(user1DaiBefore, two).toString())
      })

      it('does not take more dai than needed when repaying', async () => {
        const user1DaiBefore = (await dai.balanceOf(user1)).toString()

        await daiProxy.repayMinimumEDaiDebtForDai(pool.address, WETH, maturity1, user1, ZERO, two, {
          from: user1,
        })

        const user1DaiAfter = (await dai.balanceOf(user1)).toString()

        assert.equal((await controller.debtEDai(WETH, maturity1, user1)).toString(), ZERO)
        expect(bnify(user1DaiAfter).lt(bnify(user1DaiBefore))).to.be.true
      })

      it("doesn't repay debt if limit not reached", async () => {
        await expectRevert(
          daiProxy.repayMinimumEDaiDebtForDai(pool.address, WETH, maturity1, user2, two, one, { from: user1 }),
          'YieldProxy: Not enough eDai debt repaid'
        )
      })

      it('repays eDai debt with maximum dai', async () => {
        const user2DebtBefore = (await controller.debtEDai(WETH, maturity1, user2)).toString()
        const user1DaiBefore = (await dai.balanceOf(user1)).toString()

        await daiProxy.repayEDaiDebtForMaximumDai(pool.address, WETH, maturity1, user2, one, two, {
          from: user1,
        })

        const user2DebtAfter = (await controller.debtEDai(WETH, maturity1, user2)).toString()
        const user1DaiAfter = (await dai.balanceOf(user1)).toString()

        expect(bnify(user1DaiAfter).lt(bnify(user1DaiBefore))).to.be.true
        assert.equal(user2DebtAfter, subBN(user2DebtBefore, one).toString())
      })

      it('does not take more dai than needed when repaying', async () => {
        const user1DaiBefore = (await dai.balanceOf(user1)).toString()

        await daiProxy.repayEDaiDebtForMaximumDai(pool.address, WETH, maturity1, user1, one, two, {
          from: user1,
        })

        const user1DaiAfter = (await dai.balanceOf(user1)).toString()

        assert.equal((await controller.debtEDai(WETH, maturity1, user1)).toString(), ZERO)
        expect(bnify(user1DaiAfter).gt(subBN(user1DaiBefore, two))).to.be.true
      })

      it("doesn't repay debt if limit not reached", async () => {
        await expectRevert(
          daiProxy.repayEDaiDebtForMaximumDai(pool.address, WETH, maturity1, user2, two, one, { from: user1 }),
          'YieldProxy: Too much Dai required'
        )
      })
    })
  })
})
