const Pool = artifacts.require('Pool')
const YieldProxy = artifacts.require('YieldProxy')

import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { toWad, toRay, mulRay, chainId, bnify, MAX, name } from '../shared/utils'
import { getPermitDigest, sign, userPrivateKey } from '../shared/signatures'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('YieldProxy - LimitPool', async (accounts) => {
  let [owner, user1, operator, from, to, user2] = accounts

  // These values impact the pool results
  const rate1 = toRay(1.02)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const eDaiTokens1 = daiTokens1
  const oneToken = toWad(1)

  let maturity1: number
  let eDai1: Contract
  let limitPool: Contract
  let pool: Contract
  let dai: Contract
  let env: YieldEnvironmentLite

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai
    eDai1 = env.eDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, eDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup LimitPool
    limitPool = await YieldProxy.new(env.controller.address, [pool.address], { from: owner })

    // Allow owner to mint eDai the sneaky way, without recording a debt in controller
    await eDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })

    for (const sender of [user1, from, operator]) {
      await eDai1.approve(pool.address, -1, { from: sender })
      await dai.approve(pool.address, -1, { from: sender })
    }
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)

      await pool.init(daiReserves, { from: user1 })

      await pool.addDelegate(limitPool.address, { from: from })
    })

    it('buys dai', async () => {
      await eDai1.mint(from, eDaiTokens1, { from: owner })
      await limitPool.buyDai(pool.address, to, oneToken, oneToken.mul(2), { from: from })

      const expectedEDaiIn = new BN(oneToken.toString()).mul(new BN('100270')).div(new BN('100000'))
      const eDaiIn = new BN(eDaiTokens1.toString()).sub(new BN(await eDai1.balanceOf(from)))
      expect(eDaiIn).to.be.bignumber.gt(expectedEDaiIn.mul(new BN('9999')).div(new BN('10000')))
      expect(eDaiIn).to.be.bignumber.lt(expectedEDaiIn.mul(new BN('10001')).div(new BN('10000')))
    })

    it('buys dai with permit', async () => {
      await pool.addDelegate(limitPool.address, { from: user1 })
      await eDai1.approve(pool.address, 0, { from: user1 })
      await eDai1.mint(user1, eDaiTokens1, { from: owner })

      const digest = getPermitDigest(
        await eDai1.name(),
        await pool.eDai(),
        chainId,
        {
          owner: user1,
          spender: pool.address,
          value: MAX,
        },
        bnify(await eDai1.nonces(user1)),
        MAX
      )
      const sig = sign(digest, userPrivateKey)

      // can use the permit signature to avoid having an `approve` transaction
      await limitPool.buyDaiWithSignature(pool.address, to, oneToken, oneToken.mul(2), sig, { from: user1 })
    })

    it("doesn't buy dai if limit exceeded", async () => {
      await eDai1.mint(from, eDaiTokens1, { from: owner })

      await expectRevert(
        limitPool.buyDai(pool.address, to, oneToken, oneToken.div(2), { from: from }),
        'YieldProxy: Limit exceeded'
      )
    })

    it('sells eDai', async () => {
      const oneToken = toWad(1)
      await eDai1.mint(from, oneToken, { from: owner })

      await limitPool.sellEDai(pool.address, to, oneToken, oneToken.div(2), { from: from })

      assert.equal(await eDai1.balanceOf(from), 0, "'From' wallet should have no eDai tokens")

      const expectedDaiOut = new BN(oneToken.toString()).mul(new BN('99732')).div(new BN('100000'))
      const daiOut = new BN(await dai.balanceOf(to))
      expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
    })

    it("doesn't sell eDai if limit not reached", async () => {
      const oneToken = toWad(1)
      await eDai1.mint(from, oneToken, { from: owner })

      await expectRevert(
        limitPool.sellEDai(pool.address, to, oneToken, oneToken.mul(2), { from: from }),
        'YieldProxy: Limit not reached'
      )
    })

    describe('with extra eDai reserves', () => {
      beforeEach(async () => {
        const additionalEDaiReserves = toWad(34.4)
        await eDai1.mint(operator, additionalEDaiReserves, { from: owner })
        await pool.sellEDai(operator, operator, additionalEDaiReserves, { from: operator })
        await env.maker.getDai(from, daiTokens1, rate1)
      })

      it('sells dai', async () => {
        await limitPool.sellDai(pool.address, to, oneToken, oneToken.div(2), { from: from })

        assert.equal(
          await dai.balanceOf(from),
          daiTokens1.sub(oneToken).toString(),
          "'From' wallet should have " + daiTokens1.sub(oneToken) + ' dai tokens'
        )

        const expectedEDaiOut = new BN(oneToken.toString()).mul(new BN('117440')).div(new BN('100000'))
        const eDaiOut = new BN(await eDai1.balanceOf(to))
        // This is the lowest precision achieved.
        expect(eDaiOut).to.be.bignumber.gt(expectedEDaiOut.mul(new BN('999')).div(new BN('1000')))
        expect(eDaiOut).to.be.bignumber.lt(expectedEDaiOut.mul(new BN('1001')).div(new BN('1000')))
      })

      it("doesn't sell dai if limit not reached", async () => {
        await expectRevert(
          limitPool.sellDai(pool.address, to, oneToken, oneToken.mul(2), { from: from }),
          'YieldProxy: Limit not reached'
        )
      })

      it('buys eDai', async () => {
        await limitPool.buyEDai(pool.address, to, oneToken, oneToken.mul(2), { from: from })

        assert.equal(await eDai1.balanceOf(to), oneToken.toString(), "'To' wallet should have 1 eDai token")

        const expectedDaiIn = new BN(oneToken.toString()).mul(new BN('85110')).div(new BN('100000'))
        const daiIn = new BN(daiTokens1.toString()).sub(new BN(await dai.balanceOf(from)))
        expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')))
        expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')))
      })

      it("doesn't buy eDai if limit exceeded", async () => {
        await expectRevert(
          limitPool.buyEDai(pool.address, to, oneToken, oneToken.div(2), { from: from }),
          'YieldProxy: Limit exceeded'
        )
      })
    })
  })
})
