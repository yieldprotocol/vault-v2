const Pool = artifacts.require('Pool')
const BorrowProxy = artifacts.require('BorrowProxy')
const DSProxy = artifacts.require('DSProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

// @ts-ignore
import {
  WETH,
  spot,
  rate1,
  daiTokens1,
  wethTokens1,
  toWad,
  mulRay,
  bnify,
  chainId,
  name,
  ZERO,
  MAX,
} from '../shared/utils'
import { MakerEnvironment, YieldEnvironmentLite, Contract } from '../shared/fixtures'
import { getSignatureDigest, getPermitDigest, getDaiDigest, userPrivateKey, sign } from '../shared/signatures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'

// @ts-ignore
import { balance, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('YieldProxy - DSProxy', async (accounts) => {
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

  let borrowProxy: Contract

  let proxyFactory: Contract
  let proxyRegistry: Contract
  let dsProxy: Contract

  let maturity1: number
  let digest: any

  const one = toWad(1)
  const fyDaiTokens1 = daiTokens1

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

    // Setup BorrowProxy
    borrowProxy = await BorrowProxy.new(weth.address, dai.address, treasury.address, controller.address)

    // Setup DSProxyFactory and DSProxyCache
    proxyFactory = await DSProxyFactory.new({ from: owner })

    // Setup DSProxyRegistry
    proxyRegistry = await DSProxyRegistry.new(proxyFactory.address, { from: owner })

    // Allow owner to mint fyDai the sneaky way, without recording a debt in controller
    await fyDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
  })

  describe('through dsproxy', () => {
    let daiSig: any, controllerSig: any, poolSig: any

    beforeEach(async () => {
      // Sets DSProxy for user1
      await proxyRegistry.build({ from: user1 })
      dsProxy = await DSProxy.at(await proxyRegistry.proxies(user1))
      await controller.addDelegate(dsProxy.address, { from: user1 })
    })

    it('allows user to post eth', async () => {
      assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury has weth in MakerDAO')
      assert.equal(await controller.powerOf(WETH, user2), 0, 'User2 has borrowing power')

      const previousBalance = await balance.current(user1)

      const calldata = borrowProxy.contract.methods.post(user2).encodeABI()
      await dsProxy.methods['execute(address,bytes)'](borrowProxy.address, calldata, {
        from: user1,
        value: wethTokens1,
      })

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
        await borrowProxy.post(user1, { from: user1, value: wethTokens1 })
      })

      it('allows user to withdraw weth', async () => {
        const previousBalance = await balance.current(user2)

        const calldata = borrowProxy.contract.methods.withdraw(user2, wethTokens1).encodeABI()
        await dsProxy.methods['execute(address,bytes)'](borrowProxy.address, calldata, { from: user1 })

        expect(await balance.current(user2)).to.be.bignumber.gt(previousBalance)
        assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury should not not have weth in MakerDAO')
        assert.equal(await controller.powerOf(WETH, user1), 0, 'User1 should not have borrowing power')
      })

      describe('borrowing', () => {
        beforeEach(async () => {
          // Init pool
          const daiReserves = daiTokens1
          await env.maker.getDai(user1, daiReserves, rate1)
          await dai.approve(pool.address, MAX, { from: user1 })
          await fyDai1.approve(pool.address, MAX, { from: user1 })
          await pool.mint(user1, user1, daiReserves, { from: user1 })

          // Post some more weth to controller
          await borrowProxy.post(user1, { from: user1, value: bnify(wethTokens1).mul(2).toString() })
        })

        it('borrows dai for maximum fyDai', async () => {
          const calldata = borrowProxy.contract.methods
            .borrowDaiForMaximumFYDai(pool.address, WETH, maturity1, user2, fyDaiTokens1, one)
            .encodeABI()
          await dsProxy.methods['execute(address,bytes)'](borrowProxy.address, calldata, { from: user1 })

          assert.equal(await dai.balanceOf(user2), one.toString())
        })

        it("doesn't borrow dai if limit exceeded", async () => {
          const calldata = borrowProxy.contract.methods
            .borrowDaiForMaximumFYDai(pool.address, WETH, maturity1, user2, fyDaiTokens1, daiTokens1)
            .encodeABI()
          await expectRevert(
            dsProxy.methods['execute(address,bytes)'](borrowProxy.address, calldata, { from: user1 }),
            'YieldProxy: Too much fyDai required'
          )
        })

        describe('repaying', () => {
          beforeEach(async () => {
            const calldata = borrowProxy.contract.methods
              .borrowDaiForMaximumFYDai(pool.address, WETH, maturity1, user2, fyDaiTokens1, one)
              .encodeABI()
            await dsProxy.methods['execute(address,bytes)'](borrowProxy.address, calldata, { from: user1 })

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
              MAX
            )
            daiSig = sign(digest, userPrivateKey)

            // Authorize the proxy for the controller
            digest = getSignatureDigest(
              name,
              controller.address,
              chainId,
              {
                user: user1,
                delegate: dsProxy.address,
              },
              await controller.signatureCount(user1),
              MAX
            )
            controllerSig = sign(digest, userPrivateKey)
          })

          it('repays debt with Dai and with signature', async () => {
            await maker.getDai(user1, daiTokens1, rate1)
            const debt = (await controller.debtDai(WETH, maturity1, user1)).toString()

            // Revoke delegation, so that we test the signature.
            await controller.revokeDelegate(dsProxy.address, { from: user1 })

            const calldata = borrowProxy.contract.methods
              .repayDaiWithSignature(WETH, maturity1, user1, debt, daiSig, controllerSig)
              .encodeABI()
            await dsProxy.methods['execute(address,bytes)'](borrowProxy.address, calldata, { from: user1 })

            assert.equal((await controller.debtDai(WETH, maturity1, user1)).toString(), ZERO)
          })
        })
      })
    })
  })
})
