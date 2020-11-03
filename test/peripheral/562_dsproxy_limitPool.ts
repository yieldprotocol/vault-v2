const Pool = artifacts.require('Pool')
const YieldProxy = artifacts.require('YieldProxy')
const DSProxy = artifacts.require('DSProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

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
  const fyDaiTokens1 = daiTokens1
  const oneToken = toWad(1)

  let maturity1: number
  let fyDai1: Contract
  let limitPool: Contract
  let pool: Contract
  let dai: Contract

  let proxyFactory: Contract
  let proxyRegistry: Contract
  let dsProxy: Contract

  let env: YieldEnvironmentLite

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai
    fyDai1 = env.fyDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, fyDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup LimitPool
    limitPool = await YieldProxy.new(env.controller.address, [pool.address], { from: owner })

    // Allow owner to mint fyDai the sneaky way, without recording a debt in controller
    await fyDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })

    for (const sender of [user1, from, operator]) {
      await fyDai1.approve(pool.address, -1, { from: sender })
      await dai.approve(pool.address, -1, { from: sender })
    }

    // Setup DSProxyFactory and DSProxyCache
    proxyFactory = await DSProxyFactory.new({ from: owner })

    // Setup DSProxyRegistry
    proxyRegistry = await DSProxyRegistry.new(proxyFactory.address, { from: owner })
  })

  describe('directly', () => {
    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)
      await pool.mint(user1, user1, daiReserves, { from: user1 })
      await fyDai1.mint(user1, fyDaiTokens1, { from: owner })

      await pool.addDelegate(limitPool.address, { from: user1 })
    })

    it('buys dai', async () => {
      await limitPool.buyDai(pool.address, to, oneToken, oneToken.mul(2), { from: user1 })

      const expectedFYDaiIn = new BN(oneToken.toString()).mul(new BN('100270')).div(new BN('100000'))
      const fyDaiIn = new BN(fyDaiTokens1.toString()).sub(new BN(await fyDai1.balanceOf(user1)))
      expect(fyDaiIn).to.be.bignumber.gt(expectedFYDaiIn.mul(new BN('9999')).div(new BN('10000')))
      expect(fyDaiIn).to.be.bignumber.lt(expectedFYDaiIn.mul(new BN('10001')).div(new BN('10000')))
    })

    it('buys dai with permit', async () => {
      const digest = getPermitDigest(
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
      const sig = sign(digest, userPrivateKey)

      // can use the permit signature to avoid having an `approve` transaction
      await limitPool.buyDaiWithSignature(pool.address, to, oneToken, oneToken.mul(2), sig, { from: user1 })
    })

    it("doesn't buy dai if limit exceeded", async () => {
      await expectRevert(
        limitPool.buyDai(pool.address, to, oneToken, oneToken.div(2), { from: user1 }),
        'YieldProxy: Limit exceeded'
      )
    })
  })

  describe('through dsproxy', () => {
    beforeEach(async () => {
      const daiReserves = daiTokens1
      await env.maker.getDai(user1, daiReserves, rate1)
      await pool.mint(user1, user1, daiReserves, { from: user1 })
      await fyDai1.mint(user1, fyDaiTokens1, { from: owner })

      // Sets DSProxy for user1
      await proxyRegistry.build({ from: user1 })
      dsProxy = await DSProxy.at(await proxyRegistry.proxies(user1))
      await pool.addDelegate(dsProxy.address, { from: user1 })
    })

    it('buys dai', async () => {
      const calldata = limitPool.contract.methods.buyDai(pool.address, to, oneToken, oneToken.mul(2)).encodeABI()
      await dsProxy.methods['execute(address,bytes)'](limitPool.address, calldata, { from: user1 })

      const expectedFYDaiIn = new BN(oneToken.toString()).mul(new BN('100270')).div(new BN('100000'))
      const fyDaiIn = new BN(fyDaiTokens1.toString()).sub(new BN(await fyDai1.balanceOf(user1)))
      expect(fyDaiIn).to.be.bignumber.gt(expectedFYDaiIn.mul(new BN('9999')).div(new BN('10000')))
      expect(fyDaiIn).to.be.bignumber.lt(expectedFYDaiIn.mul(new BN('10001')).div(new BN('10000')))
    })


    it('buys dai with permit', async () => {
      const digest = getPermitDigest(
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
      const sig = sign(digest, userPrivateKey)

      const calldata = limitPool.contract.methods.buyDaiWithSignature(pool.address, to, oneToken, oneToken.mul(2), sig).encodeABI()
      await dsProxy.methods['execute(address,bytes)'](limitPool.address, calldata, { from: user1 })
    })

    it("doesn't buy dai if limit exceeded", async () => {
      const calldata = limitPool.contract.methods.buyDai(pool.address, to, oneToken, oneToken.div(2)).encodeABI()

      await expectRevert(
        dsProxy.methods['execute(address,bytes)'](limitPool.address, calldata, { from: user1 }),
        'YieldProxy: Limit exceeded'
      )
    })
  })
})
