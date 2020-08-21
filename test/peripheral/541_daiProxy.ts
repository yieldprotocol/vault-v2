const Pool = artifacts.require('Pool')
const DaiProxy = artifacts.require('DaiProxy')

import { WETH, wethTokens1, toWad, toRay, subBN, mulRay } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'
import { getSignatureDigest } from '../shared/signatures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { ecsign } from 'ethereumjs-util'

// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('DaiProxy', async (accounts) => {
  let [owner, user1, user2, operator] = accounts

  // this is the SECOND account that buidler creates
  // https://github.com/nomiclabs/buidler/blob/d399a60452f80a6e88d974b2b9205f4894a60d29/packages/buidler-core/src/internal/core/config/default-config.ts#L46
  const userPrivateKey = Buffer.from('d49743deccbccc5dc7baa8e69e5be03298da8688a15dd202e20f15d5e0e9a9fb', 'hex')
  const chainId = 31337 // buidlerevm chain id
  const name = 'Yield'
  const deadline = 100000000000000
  const SIGNATURE_TYPEHASH = keccak256(
    toUtf8Bytes('Signature(address user,address delegate,uint256 nonce,uint256 deadline)')
  )
  let digestController: any
  let digestPool: any

  // These values impact the pool results
  const rate1 = toRay(1.4)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const yDaiTokens1 = daiTokens1

  let maturity1: number
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
    weth = env.maker.weth
    dai = env.maker.dai
    treasury = env.treasury
    controller = env.controller

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    yDai1 = await env.newYDai(maturity1, 'Name', 'Symbol')

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup DaiProxy
    daiProxy = await DaiProxy.new(dai.address, controller.address, pool.address, {
      from: owner,
    })

    // Create the signature request
    const signature = {
      user: user1,
      delegate: daiProxy.address,
    }

    // Get the user's signatureCount
    const signatureCountController = await controller.signatureCount(user1)

    // Get the EIP712 digest
    digestController = getSignatureDigest(
      SIGNATURE_TYPEHASH,
      name,
      controller.address,
      chainId,
      signature,
      signatureCountController,
      deadline
    )

    // Get the user's signatureCount
    const signatureCountPool = await pool.signatureCount(user1)

    // Get the EIP712 digest
    digestPool = getSignatureDigest(
      SIGNATURE_TYPEHASH,
      name,
      pool.address,
      chainId,
      signature,
      signatureCountPool,
      deadline
    )

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

      // Post some weth to controller to be able to borrow
      await weth.deposit({ from: user1, value: wethTokens1 })
      await weth.approve(treasury.address, wethTokens1, { from: user1 })
      await controller.post(WETH, user1, user1, wethTokens1, { from: user1 })

      // Give some yDai to user1
      await yDai1.mint(user1, yDaiTokens1, { from: owner })
    })

    it('borrows dai for maximum yDai', async () => {
      const oneToken = toWad(1)

      await controller.addDelegate(daiProxy.address, { from: user1 })
      await daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, user2, yDaiTokens1, oneToken, { from: user1 })

      assert.equal(await dai.balanceOf(user2), oneToken.toString())
    })

    it('borrows dai for maximum yDai by signature', async () => {
      const oneToken = toWad(1)

      const { v, r, s } = ecsign(Buffer.from(digestController.slice(2), 'hex'), userPrivateKey)
      await daiProxy.borrowDaiForMaximumYDaiBySignature(
        WETH,
        maturity1,
        user2,
        yDaiTokens1,
        oneToken,
        deadline,
        v,
        r,
        s,
        { from: user1 }
      )

      assert.equal(await dai.balanceOf(user2), oneToken.toString())
    })

    it("doesn't borrow dai if limit exceeded", async () => {
      await controller.addDelegate(daiProxy.address, { from: user1 })

      await expectRevert(
        daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, user2, yDaiTokens1, daiTokens1, { from: user1 }),
        'DaiProxy: Too much yDai required'
      )
    })

    it('borrows minimum dai for yDai', async () => {
      const oneToken = new BN(toWad(1).toString())

      await controller.addDelegate(daiProxy.address, { from: user1 })
      await daiProxy.borrowMinimumDaiForYDai(WETH, maturity1, user2, yDaiTokens1, oneToken, { from: user1 })

      expect(await dai.balanceOf(user2)).to.be.bignumber.gt(oneToken)
      assert.equal(await yDai1.balanceOf(user1), subBN(yDaiTokens1, oneToken).toString())
    })

    it('borrows minimum dai for yDai by signature', async () => {
      const oneToken = new BN(toWad(1).toString())

      const { v, r, s } = ecsign(Buffer.from(digestController.slice(2), 'hex'), userPrivateKey)
      await daiProxy.borrowMinimumDaiForYDaiBySignature(
        WETH,
        maturity1,
        user2,
        yDaiTokens1,
        oneToken,
        deadline,
        v,
        r,
        s,
        { from: user1 }
      )

      expect(await dai.balanceOf(user2)).to.be.bignumber.gt(oneToken)
      assert.equal(await yDai1.balanceOf(user1), subBN(yDaiTokens1, oneToken).toString())
    })

    it("doesn't borrow dai if limit not reached", async () => {
      const oneToken = new BN(toWad(1).toString())
      await controller.addDelegate(daiProxy.address, { from: user1 })

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

        await pool.addDelegate(daiProxy.address, { from: user1 })
        await dai.approve(pool.address, daiTokens1, { from: user1 })
        await daiProxy.repayMinimumYDaiDebtForDai(WETH, maturity1, user2, oneYDai, twoDai, { from: user1 })

        expect(await controller.debtYDai(WETH, maturity1, user2)).to.be.bignumber.lt(yDaiDebt)
        assert.equal(await dai.balanceOf(user1), subBN(daiTokens1, twoDai).toString())
      })

      it('repays minimum yDai debt with dai by signature', async () => {
        const oneYDai = toWad(1)
        const twoDai = toWad(2)
        const yDaiDebt = new BN(daiTokens1.toString())

        const { v, r, s } = ecsign(Buffer.from(digestPool.slice(2), 'hex'), userPrivateKey)
        await dai.approve(pool.address, daiTokens1, { from: user1 })
        await daiProxy.repayMinimumYDaiDebtForDaiBySignature(
          WETH,
          maturity1,
          user2,
          oneYDai,
          twoDai,
          deadline,
          v,
          r,
          s,
          { from: user1 }
        )

        expect(await controller.debtYDai(WETH, maturity1, user2)).to.be.bignumber.lt(yDaiDebt)
        assert.equal(await dai.balanceOf(user1), subBN(daiTokens1, twoDai).toString())
      })

      it("doesn't repay debt if limit not reached", async () => {
        const oneDai = toWad(1)
        const twoYDai = toWad(2)

        await pool.addDelegate(daiProxy.address, { from: user1 })
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

        await pool.addDelegate(daiProxy.address, { from: user1 })
        await dai.approve(pool.address, daiTokens1, { from: user1 })
        await daiProxy.repayYDaiDebtForMaximumDai(WETH, maturity1, user2, oneYDai, twoDai, { from: user1 })

        expect(await dai.balanceOf(user1)).to.be.bignumber.lt(new BN(daiTokens1.toString()))
        assert.equal(await controller.debtYDai(WETH, maturity1, user2), subBN(yDaiDebt, oneYDai).toString())
      })

      it('repays yDai debt with maximum dai by signature', async () => {
        const oneYDai = toWad(1)
        const twoDai = toWad(2)
        const yDaiDebt = daiTokens1

        const { v, r, s } = ecsign(Buffer.from(digestPool.slice(2), 'hex'), userPrivateKey)
        await dai.approve(pool.address, daiTokens1, { from: user1 })
        await daiProxy.repayYDaiDebtForMaximumDaiBySignature(
          WETH,
          maturity1,
          user2,
          oneYDai,
          twoDai,
          deadline,
          v,
          r,
          s,
          { from: user1 }
        )

        expect(await dai.balanceOf(user1)).to.be.bignumber.lt(new BN(daiTokens1.toString()))
        assert.equal(await controller.debtYDai(WETH, maturity1, user2), subBN(yDaiDebt, oneYDai).toString())
      })

      it("doesn't repay debt if limit not reached", async () => {
        const oneDai = toWad(1)
        const twoYDai = toWad(2)

        await pool.addDelegate(daiProxy.address, { from: user1 })
        await dai.approve(pool.address, daiTokens1, { from: user1 })

        await expectRevert(
          daiProxy.repayYDaiDebtForMaximumDai(WETH, maturity1, user2, twoYDai, oneDai, { from: user1 }),
          'DaiProxy: Too much Dai required'
        )
      })
    })
  })
})
