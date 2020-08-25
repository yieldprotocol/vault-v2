const Pool = artifacts.require('Pool')

import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
// @ts-ignore
import { BN } from '@openzeppelin/test-helpers'
import { rate1, daiTokens1, toWad } from './../shared/utils'
import { YieldEnvironmentLite, Contract } from './../shared/fixtures'

contract('Pool', async (accounts) => {
  let [owner, user1, operator, from, to] = accounts

  const daiReserves = daiTokens1
  const yDaiTokens1 = daiTokens1
  const yDaiReserves = yDaiTokens1

  let env: YieldEnvironmentLite
  let dai: Contract
  let yDai1: Contract
  let pool: Contract

  let maturity1: number
  let snapshot: any
  let snapshotId: string

  const results = new Set()
  results.add(['trade', 'daiReserves', 'yDaiReserves', 'tokensIn', 'tokensOut'])

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000

    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai

    yDai1 = env.yDais[0]
    await yDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')))

    // Setup Pool
    pool = await Pool.new(dai.address, yDai1.address, 'Name', 'Symbol', { from: owner })
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  it('get the size of the contract', async () => {
    console.log()
    console.log('    ·--------------------|------------------|------------------|------------------·')
    console.log('    |  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |')
    console.log('    ·····················|··················|··················|···················')

    const bytecode = pool.constructor._json.bytecode
    const deployed = pool.constructor._json.deployedBytecode
    const sizeOfB = bytecode.length / 2
    const sizeOfD = deployed.length / 2
    const sizeOfC = sizeOfB - sizeOfD
    console.log(
      '    |  ' +
        pool.constructor._json.contractName.padEnd(18, ' ') +
        '|' +
        ('' + sizeOfB).padStart(16, ' ') +
        '  ' +
        '|' +
        ('' + sizeOfD).padStart(16, ' ') +
        '  ' +
        '|' +
        ('' + sizeOfC).padStart(16, ' ') +
        '  |'
    )
    console.log('    ·--------------------|------------------|------------------|------------------·')
    console.log()
  })

  describe('with liquidity', () => {
    beforeEach(async () => {
      await env.maker.getDai(user1, daiReserves, rate1)
      await yDai1.mint(user1, yDaiReserves, { from: owner })

      await dai.approve(pool.address, daiReserves, { from: user1 })
      await yDai1.approve(pool.address, yDaiReserves, { from: user1 })
      await pool.init(daiReserves, { from: user1 })
    })

    it('buys dai', async () => {
      const tradeSize = toWad(1).div(1000)
      await yDai1.mint(from, yDaiTokens1.div(1000), { from: owner })

      await pool.addDelegate(operator, { from: from })
      await yDai1.approve(pool.address, yDaiTokens1.div(1000), { from: from })
      await pool.buyDai(from, to, tradeSize, { from: operator })

      const yDaiIn = new BN(yDaiTokens1.div(1000).toString()).sub(new BN(await yDai1.balanceOf(from)))

      results.add(['buyDai', daiReserves, yDaiReserves, yDaiIn, tradeSize])
    })

    it('sells yDai', async () => {
      const tradeSize = toWad(1).div(1000)
      await yDai1.mint(from, tradeSize, { from: owner })

      await pool.addDelegate(operator, { from: from })
      await yDai1.approve(pool.address, tradeSize, { from: from })
      await pool.sellYDai(from, to, tradeSize, { from: operator })

      const daiOut = new BN(await dai.balanceOf(to))
      results.add(['sellYDai', daiReserves, yDaiReserves, tradeSize, daiOut])
    })

    describe('with extra yDai reserves', () => {
      beforeEach(async () => {
        const additionalYDaiReserves = toWad(34.4)
        await yDai1.mint(operator, additionalYDaiReserves, { from: owner })
        await yDai1.approve(pool.address, additionalYDaiReserves, { from: operator })
        await pool.sellYDai(operator, operator, additionalYDaiReserves, { from: operator })
      })

      it('sells dai', async () => {
        const tradeSize = toWad(1).div(1000)
        await env.maker.getDai(from, daiTokens1, rate1)

        await pool.addDelegate(operator, { from: from })
        await dai.approve(pool.address, tradeSize, { from: from })
        await pool.sellDai(from, to, tradeSize, { from: operator })

        const yDaiOut = new BN(await yDai1.balanceOf(to))

        results.add(['sellDai', daiReserves, yDaiReserves, tradeSize, yDaiOut])
      })

      it('buys yDai', async () => {
        const tradeSize = toWad(1).div(1000)
        await env.maker.getDai(from, daiTokens1.div(1000), rate1)

        await pool.addDelegate(operator, { from: from })
        await dai.approve(pool.address, daiTokens1.div(1000), { from: from })
        await pool.buyYDai(from, to, tradeSize, { from: operator })

        const daiIn = new BN(daiTokens1.div(1000).toString()).sub(new BN(await dai.balanceOf(from)))
        results.add(['buyYDai', daiReserves, yDaiReserves, daiIn, tradeSize])
      })

      it('prints results', async () => {
        let line: string[]
        // @ts-ignore
        for (line of results.values()) {
          console.log(
            '| ' +
              line[0].padEnd(10, ' ') +
              '· ' +
              line[1].toString().padEnd(23, ' ') +
              '· ' +
              line[2].toString().padEnd(23, ' ') +
              '· ' +
              line[3].toString().padEnd(23, ' ') +
              '· ' +
              line[4].toString().padEnd(23, ' ') +
              '|'
          )
        }
      })
    })
  })
})
