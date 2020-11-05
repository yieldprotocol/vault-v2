const Pool = artifacts.require('Pool')
const BorrowProxy = artifacts.require('BorrowProxy')

import { WETH, wethTokens1, toWad, toRay, mulRay, bnify, chainId, name, MAX } from '../shared/utils'
import { getSignatureDigest, getDaiDigest, getPermitDigest, userPrivateKey, sign } from '../shared/signatures'
import { MakerEnvironment, YieldEnvironmentLite, Contract } from '../shared/fixtures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { assert } from 'chai'

contract('BorrowProxy - Signatures', async (accounts) => {
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
    proxy = await BorrowProxy.new(weth.address, dai.address, treasury.address, controller.address, { from: owner })

    // Allow owner to mint fyDai the sneaky way, without recording a debt in controller
    await fyDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
  })

  describe('collateral', () => {
    let controllerSig: any

    describe('with posted eth', () => {
      beforeEach(async () => {
        await proxy.post(user1, { from: user1, value: wethTokens1 })

        // Authorize the proxy for the controller
        const controllerDigest = getSignatureDigest(
          name,
          controller.address,
          chainId,
          {
            user: user1,
            delegate: proxy.address,
          },
          await controller.signatureCount(user1),
          MAX
        )
        controllerSig = sign(controllerDigest, userPrivateKey)
      })

      it('allows user to withdraw weth', async () => {
        await proxy.withdrawWithSignature(user2, wethTokens1, controllerSig, { from: user1 })
      })

      describe('borrowing', () => {
        beforeEach(async () => {
          // Init pool
          const daiReserves = daiTokens1
          await env.maker.getDai(user1, daiReserves.mul(2).toString(), rate1)
          await dai.approve(pool.address, MAX, { from: user1 })
          await fyDai1.approve(pool.address, MAX, { from: user1 })
          await pool.mint(user1, user1, daiReserves, { from: user1 })

          // Post some more weth to the controller
          await proxy.post(user1, { from: user1, value: bnify(wethTokens1).mul(2).toString() })

          // Give some fyDai to user1
          await fyDai1.mint(user1, fyDaiTokens1, { from: owner })
        })

        it('borrows dai for maximum fyDai', async () => {
          await proxy.borrowDaiForMaximumFYDaiWithSignature(
            pool.address,
            WETH,
            maturity1,
            user2,
            fyDaiTokens1,
            oneToken,
            controllerSig,
            {
              from: user1,
            }
          )

          assert.equal(await dai.balanceOf(user2), oneToken.toString())
        })

        it("doesn't borrow dai if limit exceeded", async () => {
          await expectRevert(
            proxy.borrowDaiForMaximumFYDaiWithSignature(
              pool.address,
              WETH,
              maturity1,
              user2,
              fyDaiTokens1,
              daiTokens1,
              controllerSig,
              {
                from: user1,
              }
            ),
            'YieldProxy: Too much fyDai required'
          )
        })

        describe('repaying', () => {
          let daiSig: any

          beforeEach(async () => {
            await controller.addDelegate(proxy.address, { from: user1 })
            await proxy.borrowDaiForMaximumFYDai(pool.address, WETH, maturity1, user2, fyDaiTokens1, oneToken, {
              from: user1,
            })

            // Authorize DAI
            const daiDigest = getDaiDigest(
              await dai.name(),
              dai.address,
              chainId,
              {
                owner: user1,
                spender: treasury.address,
                can: true,
              },
              bnify(await dai.nonces(user1)),
              MAX
            )
            daiSig = sign(daiDigest, userPrivateKey)
          })

          it('repays debt using Dai with Dai permit ', async () => {
            await proxy.repayDaiWithSignature(WETH, maturity1, user2, oneToken, daiSig, '0x', {
              from: user1,
            })
          })

          it('repays debt using Dai with signatures ', async () => {
            await controller.revokeDelegate(proxy.address, { from: user1 })

            await proxy.repayDaiWithSignature(WETH, maturity1, user2, oneToken, daiSig, controllerSig, {
              from: user1,
            })
          })
        })
      })
    })
  })

  describe('lend', () => {
    let poolSig: any
    let fyDaiSig: any

    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(owner, daiReserves, rate1)

      await fyDai1.approve(pool.address, -1, { from: owner })
      await dai.approve(pool.address, -1, { from: owner })
      await pool.mint(owner, owner, daiReserves, { from: owner })

      // Authorize the proxy for the pool
      const poolDigest = getSignatureDigest(
        name,
        pool.address,
        chainId,
        {
          user: user1,
          delegate: proxy.address,
        },
        await pool.signatureCount(user1),
        MAX
      )
      poolSig = sign(poolDigest, userPrivateKey)

      const fyDaiDigest = getPermitDigest(
        await fyDai1.name(),
        await pool.fyDai(),
        chainId,
        {
          owner: user1,
          spender: pool.address,
          value: MAX,
        },
        bnify(await fyDai1.nonces(user1)),
        MAX
      )
      fyDaiSig = sign(fyDaiDigest, userPrivateKey)
    })

    it('buys dai with signatures', async () => {
      await fyDai1.mint(user1, fyDaiTokens1, { from: owner })
      await proxy.buyDaiWithSignature(pool.address, user2, oneToken, oneToken.mul(2), fyDaiSig, poolSig, {
        from: user1,
      })
    })

    it('sells fyDai with signatures', async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(user1, oneToken, { from: owner })

      await proxy.sellFYDaiWithSignature(pool.address, user2, oneToken, oneToken.div(2), fyDaiSig, poolSig, {
        from: user1,
      })
    })
  })
})
