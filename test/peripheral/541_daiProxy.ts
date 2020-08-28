const Pool = artifacts.require('Pool')
const DaiProxy = artifacts.require('YieldProxy')

import { WETH, rate1, daiTokens1, wethTokens1, toWad, toRay, subBN, mulRay, bnify } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'
import { getSignatureDigest, getPermitDigest, getDaiDigest, getChaiDigest } from '../shared/signatures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { ecsign } from 'ethereumjs-util'

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'
import { BigNumber } from 'ethers'

contract('YieldProxy - DaiProxy', async (accounts) => {
  let [owner, user1, user2, operator] = accounts

  let maturity1: number
  let weth: Contract
  let dai: Contract
  let controller: Contract
  let yDai1: Contract
  let pool: Contract
  let daiProxy: Contract
  let env: YieldEnvironmentLite

  const one = toWad(1)
  const two = toWad(2)
  const yDaiTokens1 = daiTokens1
  const yDaiDebt = daiTokens1

  const MAX = bnify('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')

  const userPrivateKey = Buffer.from('d49743deccbccc5dc7baa8e69e5be03298da8688a15dd202e20f15d5e0e9a9fb', 'hex')
  const chainId = 31337 // buidlerevm chain id
  const name = 'Yield'
  let digest: any

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    weth = env.maker.weth
    dai = env.maker.dai
    controller = env.controller

    yDai1 = env.yDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup DaiProxy
    daiProxy = await DaiProxy.new(env.controller.address, [pool.address])

    // Allow owner to mint yDai the sneaky way, without recording a debt in controller
    await yDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })

    const sign = (digest: any, privateKey: any) => {
      const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), privateKey)
      return '0x' + r.toString('hex') + s.toString('hex') + v.toString(16)
    }

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

    // Authorize YDai for the pool
    digest = getPermitDigest(
      await yDai1.name(),
      await pool.yDai(),
      chainId,
      {
        owner: user1,
        spender: daiProxy.address,
        value: MAX,
      },
      bnify(await yDai1.nonces(user1)),
      MAX
    )
    const ydaiSig = sign(digest, userPrivateKey)

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
    await daiProxy.authorizePool(pool.address, user1, daiSig2, ydaiSig, poolSig, { from: operator })
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      // Init pool
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)
      await dai.approve(pool.address, MAX, { from: user1 })
      await yDai1.approve(pool.address, MAX, { from: user1 })
      await pool.init(daiReserves, { from: user1 })

      // Post some weth to controller via the proxy to be able to borrow
      // without requiring an `approve`!
      await daiProxy.post(user1, { from: user1, value: bnify(wethTokens1).mul(2).toString() })

      // Give some yDai to user1
      await yDai1.mint(user1, yDaiTokens1, { from: owner })
    })

    it('fails on unknown pools', async () => {
      const fakePoolContract = await Pool.new(dai.address, yDai1.address, 'Fake', 'Fake')
      const fakePool = fakePoolContract.address

      await expectRevert(daiProxy.addLiquidity(fakePool, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.removeLiquidityEarly(fakePool, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.removeLiquidityMature(fakePool, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.borrowDaiForMaximumYDai(fakePool, WETH, 1, owner, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(daiProxy.borrowMinimumDaiForYDai(fakePool, WETH, 1, owner, 1, 1), 'YieldProxy: Unknown pool')
      await expectRevert(
        daiProxy.repayMinimumYDaiDebtForDai(fakePool, WETH, 1, owner, 1, 1),
        'YieldProxy: Unknown pool'
      )
      await expectRevert(
        daiProxy.repayYDaiDebtForMaximumDai(fakePool, WETH, 1, owner, 1, 1),
        'YieldProxy: Unknown pool'
      )
    })

    it('borrows dai for maximum yDai', async () => {
      await daiProxy.borrowDaiForMaximumYDai(pool.address, WETH, maturity1, user2, yDaiTokens1, one, {
        from: user1,
      })

      assert.equal(await dai.balanceOf(user2), one.toString())
    })

    it("doesn't borrow dai if limit exceeded", async () => {
      await expectRevert(
        daiProxy.borrowDaiForMaximumYDai(pool.address, WETH, maturity1, user2, yDaiTokens1, daiTokens1, {
          from: user1,
        }),
        'YieldProxy: Too much yDai required'
      )
    })

    it('borrows minimum dai for yDai', async () => {
      const balanceBefore = bnify(await yDai1.balanceOf(user1))
      const balanceBefore2 = bnify(await dai.balanceOf(user2))
      await daiProxy.borrowMinimumDaiForYDai(pool.address, WETH, maturity1, user2, yDaiTokens1, one, {
        from: user1,
      })
      const balanceAfter = bnify(await yDai1.balanceOf(user1))
      const balanceAfter2 = bnify(await dai.balanceOf(user2))

      // user1's balance remains the same
      expect(balanceAfter.eq(balanceBefore)).to.be.true

      // user2 got >1 DAI
      expect(balanceAfter2.gt(balanceBefore2.add(one))).to.be.true
    })

    it("doesn't borrow dai if limit not reached", async () => {
      await expectRevert(
        daiProxy.borrowMinimumDaiForYDai(pool.address, WETH, maturity1, user2, one, daiTokens1, { from: user1 }),
        'YieldProxy: Not enough Dai obtained'
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
        await daiProxy.post(user2, { from: user2, value: bnify(wethTokens1).mul(2).toString() })
        await controller.borrow(WETH, maturity1, user2, user2, daiTokens1, { from: user2 })

        // Give some Dai to `user1`
        await env.maker.getDai(user1, daiTokens1, rate1)
      })

      it('repays minimum yDai debt with dai', async () => {
        await daiProxy.repayMinimumYDaiDebtForDai(pool.address, WETH, maturity1, user2, one, two, {
          from: user1,
        })

        const debt = bnify((await controller.debtYDai(WETH, maturity1, user2)).toString())
        expect(debt.lt(yDaiDebt)).to.be.true
        assert.equal(await dai.balanceOf(user1), subBN(daiTokens1, two).toString())
      })

      it("doesn't repay debt if limit not reached", async () => {
        await expectRevert(
          daiProxy.repayMinimumYDaiDebtForDai(pool.address, WETH, maturity1, user2, two, one, { from: user1 }),
          'YieldProxy: Not enough yDai debt repaid'
        )
      })

      it('repays yDai debt with maximum dai', async () => {
        await daiProxy.repayYDaiDebtForMaximumDai(pool.address, WETH, maturity1, user2, one, two, {
          from: user1,
        })

        const balance = bnify(await dai.balanceOf(user1))
        expect(balance.lt(daiTokens1)).to.be.true
        assert.equal(await controller.debtYDai(WETH, maturity1, user2), subBN(yDaiDebt, one).toString())
      })

      it("doesn't repay debt if limit not reached", async () => {
        await expectRevert(
          daiProxy.repayYDaiDebtForMaximumDai(pool.address, WETH, maturity1, user2, two, one, { from: user1 }),
          'YieldProxy: Too much Dai required'
        )
      })
    })
  })
})
