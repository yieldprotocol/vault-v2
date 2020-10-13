const Pool = artifacts.require('Pool')

import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
import { toWad, toRay, mulRay } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { assert, expect } from 'chai'

contract('Pool', async (accounts) => {
  let [owner, user1, user2, operator, from, to] = accounts

  // These values impact the pool results
  const rate1 = toRay(1.02)
  const daiDebt1 = toWad(96)
  const daiTokens1 = mulRay(daiDebt1, rate1)
  const fyDaiTokens1 = daiTokens1

  const oneToken = toWad(1)
  const initialDai = daiTokens1

  let snapshot: any
  let snapshotId: string

  let env: YieldEnvironmentLite

  let dai: Contract
  let pool: Contract
  let fyDai1: Contract

  let maturity1: number

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup fyDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai
    fyDai1 = env.fyDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, fyDai1.address, 'Name', 'Symbol', { from: owner })

    // Allow owner to mint fyDai the sneaky way, without recording a debt in controller
    await fyDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
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

  it('should setup pool', async () => {
    const b = new BN('18446744073709551615')
    const k = b.div(new BN('126144000'))
    expect(await pool.k()).to.be.bignumber.equal(k)

    const g1 = new BN('950').mul(b).div(new BN('1000')).add(new BN(1)) // Sell Dai to the pool
    const g2 = new BN('1000').mul(b).div(new BN('950')).add(new BN(1)) // Sell fyDai to the pool
  })

  it('adds initial liquidity', async () => {
    await env.maker.getDai(user1, initialDai, rate1)

    console.log('        initial liquidity...')
    console.log('        daiReserves: %d', initialDai.toString())

    await dai.approve(pool.address, initialDai, { from: user1 })
    // await fyDai1.approve(pool.address, fyDaiTokens1, { from: user1 });
    const tx = await pool.mint(user1, user1, initialDai, { from: user1 })
    const event = tx.logs[tx.logs.length - 1]

    assert.equal(event.event, 'Liquidity')
    assert.equal(event.args.from, user1)
    assert.equal(event.args.to, user1)
    assert.equal(event.args.daiTokens.toString(), initialDai.mul(-1).toString())
    assert.equal(event.args.fyDaiTokens.toString(), 0)
    assert.equal(event.args.poolTokens.toString(), initialDai.toString())

    assert.equal(
      await pool.balanceOf(user1),
      initialDai.toString(),
      'User1 should have ' + initialDai + ' liquidity tokens'
    )
  })

  describe('with initial liquidity', () => {
    beforeEach(async () => {
      await env.maker.getDai(user1, initialDai, rate1)

      await dai.approve(pool.address, initialDai, { from: user1 })
      await pool.mint(user1, user1, initialDai, { from: user1 })
    })

    it('sells fyDai', async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(from, oneToken, { from: owner })

      // daiOutForFYDaiIn formula: https://www.desmos.com/calculator/7knilsjycu

      console.log('          selling fyDai...')
      console.log('          daiReserves: %d', await pool.getDaiReserves())
      console.log('          fyDaiReserves: %d', await pool.getFYDaiReserves())
      console.log('          fyDaiIn: %d', oneToken.toString())
      console.log('          k: %d', await pool.k())
      console.log('          g2: %d', await pool.g2())
      const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
      console.log('          timeTillMaturity: %d', new BN(maturity1).sub(t).toString())

      assert.equal(
        await dai.balanceOf(to),
        0,
        "'To' wallet should have no dai, instead has " + (await dai.balanceOf(to))
      )

      // Test preview since we are here
      const daiOutPreview = await pool.sellFYDaiPreview(oneToken, { from: operator })

      await pool.addDelegate(operator, { from: from })
      await fyDai1.approve(pool.address, oneToken, { from: from })
      const event = (await pool.sellFYDai(from, to, oneToken, { from: operator })).logs[3]

      const expectedDaiOut = new BN(oneToken.toString()).mul(new BN('99732')).div(new BN('100000'))
      const daiOut = new BN(await dai.balanceOf(to))

      assert.equal(event.event, 'Trade')
      assert.equal(event.args.from, from)
      assert.equal(event.args.to, to)
      assert.equal(event.args.daiTokens, (await dai.balanceOf(to)).toString())
      assert.equal(event.args.fyDaiTokens, oneToken.mul(-1).toString())

      assert.equal(await fyDai1.balanceOf(from), 0, "'From' wallet should have no fyDai tokens")

      expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.gt(daiOutPreview.mul(new BN('9999')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.lt(daiOutPreview.mul(new BN('10001')).div(new BN('10000')))
    })

    it('buys dai', async () => {
      const oneToken = toWad(1)
      await fyDai1.mint(from, fyDaiTokens1, { from: owner })

      // fyDaiInForDaiOut formula: https://www.desmos.com/calculator/c1scsshbzh

      console.log('          buying dai...')
      console.log('          daiReserves: %d', await pool.getDaiReserves())
      console.log('          fyDaiReserves: %d', await pool.getFYDaiReserves())
      console.log('          daiOut: %d', oneToken.toString())
      console.log('          k: %d', await pool.k())
      console.log('          g2: %d', await pool.g2())
      const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
      console.log('          timeTillMaturity: %d', new BN(maturity1).sub(t).toString())

      assert.equal(
        await fyDai1.balanceOf(from),
        fyDaiTokens1.toString(),
        "'From' wallet should have " + fyDaiTokens1 + ' fyDai, instead has ' + (await fyDai1.balanceOf(from))
      )

      // Test preview since we are here
      const fyDaiInPreview = await pool.buyDaiPreview(oneToken, { from: operator })

      await pool.addDelegate(operator, { from: from })
      await fyDai1.approve(pool.address, fyDaiTokens1, { from: from })
      const event = (await pool.buyDai(from, to, oneToken, { from: operator })).logs[3]

      const expectedFYDaiIn = new BN(oneToken.toString()).mul(new BN('100270')).div(new BN('100000'))
      const fyDaiIn = new BN(fyDaiTokens1.toString()).sub(new BN(await fyDai1.balanceOf(from)))

      assert.equal(event.event, 'Trade')
      assert.equal(event.args.from, from)
      assert.equal(event.args.to, to)
      assert.equal(event.args.daiTokens, oneToken.toString())
      assert.equal(event.args.fyDaiTokens, fyDaiIn.mul(new BN('-1')).toString())

      assert.equal(await dai.balanceOf(to), oneToken.toString(), 'Receiver account should have 1 dai token')

      expect(fyDaiIn).to.be.bignumber.gt(expectedFYDaiIn.mul(new BN('9999')).div(new BN('10000')))
      expect(fyDaiIn).to.be.bignumber.lt(expectedFYDaiIn.mul(new BN('10001')).div(new BN('10000')))
      expect(fyDaiIn).to.be.bignumber.gt(fyDaiInPreview.mul(new BN('9999')).div(new BN('10000')))
      expect(fyDaiIn).to.be.bignumber.lt(fyDaiInPreview.mul(new BN('10001')).div(new BN('10000')))
    })

    describe('with extra fyDai reserves', () => {
      beforeEach(async () => {
        const additionalFYDaiReserves = toWad(34.4)
        await fyDai1.mint(operator, additionalFYDaiReserves, { from: owner })
        await fyDai1.approve(pool.address, additionalFYDaiReserves, { from: operator })
        await pool.sellFYDai(operator, operator, additionalFYDaiReserves, { from: operator })
      })

      it('mints liquidity tokens', async () => {
        // Use this to test: https://www.desmos.com/calculator/mllhtohxfx

        console.log('          minting liquidity tokens...')
        console.log('          Real daiReserves: %d', await dai.balanceOf(pool.address))
        console.log('          Real fyDaiReserves: %d', await fyDai1.balanceOf(pool.address))
        console.log('          Pool supply: %d', await pool.totalSupply())
        console.log('          daiIn: %d', oneToken.toString())

        await dai.mint(user1, oneToken, { from: owner }) // Not feeling like fighting with Vat
        await fyDai1.mint(user1, fyDaiTokens1, { from: owner })

        const fyDaiBefore = new BN(await fyDai1.balanceOf(user1))
        const poolTokensBefore = new BN(await pool.balanceOf(user2))

        await dai.approve(pool.address, oneToken, { from: user1 })
        await fyDai1.approve(pool.address, fyDaiTokens1, { from: user1 })
        const tx = await pool.mint(user1, user2, oneToken, { from: user1 })
        const event = tx.logs[tx.logs.length - 1]

        const expectedMinted = new BN('1473236946700000000')
        const expectedFYDaiIn = new BN('517558731280000000')

        const minted = new BN(await pool.balanceOf(user2)).sub(poolTokensBefore)
        const fyDaiIn = fyDaiBefore.sub(new BN(await fyDai1.balanceOf(user1)))

        assert.equal(event.event, 'Liquidity')
        assert.equal(event.args.from, user1)
        assert.equal(event.args.to, user2)
        assert.equal(event.args.daiTokens, oneToken.mul(-1).toString())

        expect(minted).to.be.bignumber.gt(expectedMinted.mul(new BN('9999')).div(new BN('10000')))
        expect(minted).to.be.bignumber.lt(expectedMinted.mul(new BN('10001')).div(new BN('10000')))

        expect(fyDaiIn).to.be.bignumber.gt(expectedFYDaiIn.mul(new BN('9999')).div(new BN('10000')))
        expect(fyDaiIn).to.be.bignumber.lt(expectedFYDaiIn.mul(new BN('10001')).div(new BN('10000')))

        assert.equal(event.args.fyDaiTokens, fyDaiIn.mul(new BN('-1')).toString())
        assert.equal(event.args.poolTokens, minted.toString())
      })

      it('burns liquidity tokens', async () => {
        // Use this to test: https://www.desmos.com/calculator/ubsalzunpo

        console.log('          burning liquidity tokens...')
        console.log('          Real daiReserves: %d', await dai.balanceOf(pool.address))
        console.log('          Real fyDaiReserves: %d', await fyDai1.balanceOf(pool.address))
        console.log('          Pool supply: %d', await pool.totalSupply())
        console.log('          Burned: %d', oneToken.toString())

        const fyDaiReservesBefore = new BN(await fyDai1.balanceOf(pool.address))
        const daiReservesBefore = new BN(await dai.balanceOf(pool.address))

        await pool.approve(pool.address, oneToken, { from: user1 })
        const tx = await pool.burn(user1, user2, oneToken, { from: user1 })
        const event = tx.logs[tx.logs.length - 1]

        const expectedFYDaiOut = new BN('351307189540000000')
        const expectedDaiOut = new BN('678777437820000000')

        const fyDaiOut = fyDaiReservesBefore.sub(new BN(await fyDai1.balanceOf(pool.address)))
        const daiOut = daiReservesBefore.sub(new BN(await dai.balanceOf(pool.address)))

        assert.equal(event.event, 'Liquidity')
        assert.equal(event.args.from, user1)
        assert.equal(event.args.to, user2)
        assert.equal(event.args.poolTokens, oneToken.mul(-1).toString())

        expect(fyDaiOut).to.be.bignumber.gt(expectedFYDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(fyDaiOut).to.be.bignumber.lt(expectedFYDaiOut.mul(new BN('10001')).div(new BN('10000')))

        expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))

        assert.equal(event.args.fyDaiTokens, fyDaiOut.toString())
        assert.equal(event.args.daiTokens, daiOut.toString())
      })

      it('sells dai', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // fyDaiOutForDaiIn formula: https://www.desmos.com/calculator/8eczy19er3

        console.log('          selling dai...')
        console.log('          daiReserves: %d', await pool.getDaiReserves())
        console.log('          fyDaiReserves: %d', await pool.getFYDaiReserves())
        console.log('          daiIn: %d', oneToken.toString())
        console.log('          k: %d', await pool.k())
        console.log('          g1: %d', await pool.g1())
        const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
        console.log('          timeTillMaturity: %d', new BN(maturity1).sub(t).toString())

        assert.equal(
          await fyDai1.balanceOf(to),
          0,
          "'To' wallet should have no fyDai, instead has " + (await fyDai1.balanceOf(operator))
        )

        // Test preview since we are here
        const fyDaiOutPreview = await pool.sellDaiPreview(oneToken, { from: operator })

        await pool.addDelegate(operator, { from: from })
        await dai.approve(pool.address, oneToken, { from: from })
        const event = (await pool.sellDai(from, to, oneToken, { from: operator })).logs[2]

        const expectedFYDaiOut = new BN(oneToken.toString()).mul(new BN('117440')).div(new BN('100000'))
        const fyDaiOut = new BN(await fyDai1.balanceOf(to))

        assert.equal(event.event, 'Trade')
        assert.equal(event.args.from, from)
        assert.equal(event.args.to, to)
        assert.equal(event.args.daiTokens, oneToken.mul(-1).toString())
        assert.equal(event.args.fyDaiTokens, fyDaiOut.toString())

        assert.equal(
          await dai.balanceOf(from),
          daiTokens1.sub(oneToken).toString(),
          "'From' wallet should have " + daiTokens1.sub(oneToken) + ' dai tokens'
        )

        expect(fyDaiOut).to.be.bignumber.gt(expectedFYDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(fyDaiOut).to.be.bignumber.lt(expectedFYDaiOut.mul(new BN('10001')).div(new BN('10000')))
        expect(fyDaiOut).to.be.bignumber.gt(fyDaiOutPreview.mul(new BN('9999')).div(new BN('10000')))
        expect(fyDaiOut).to.be.bignumber.lt(fyDaiOutPreview.mul(new BN('10001')).div(new BN('10000')))
      })

      it('buys fyDai', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // daiInForFYDaiOut formula: https://www.desmos.com/calculator/grjod0grzp

        console.log('          buying fyDai...')
        console.log('          daiReserves: %d', await pool.getDaiReserves())
        console.log('          fyDaiReserves: %d', await pool.getFYDaiReserves())
        console.log('          fyDaiOut: %d', oneToken.toString())
        console.log('          k: %d', await pool.k())
        console.log('          g1: %d', await pool.g1())
        const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
        console.log('          timeTillMaturity: %d', new BN(maturity1).sub(t).toString())

        assert.equal(
          await fyDai1.balanceOf(to),
          0,
          "'To' wallet should have no fyDai, instead has " + (await fyDai1.balanceOf(to))
        )

        // Test preview since we are here
        const daiInPreview = await pool.buyFYDaiPreview(oneToken, { from: operator })

        await pool.addDelegate(operator, { from: from })
        await dai.approve(pool.address, daiTokens1, { from: from })
        const event = (await pool.buyFYDai(from, to, oneToken, { from: operator })).logs[2]

        const expectedDaiIn = new BN(oneToken.toString()).mul(new BN('85110')).div(new BN('100000'))
        const daiIn = new BN(daiTokens1.toString()).sub(new BN(await dai.balanceOf(from)))

        assert.equal(event.event, 'Trade')
        assert.equal(event.args.from, from)
        assert.equal(event.args.to, to)
        assert.equal(event.args.daiTokens, daiIn.mul(new BN('-1')).toString())
        assert.equal(event.args.fyDaiTokens, oneToken.toString())

        assert.equal(await fyDai1.balanceOf(to), oneToken.toString(), "'To' wallet should have 1 fyDai token")

        expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')))
        expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')))
        expect(daiIn).to.be.bignumber.gt(daiInPreview.mul(new BN('9999')).div(new BN('10000')))
        expect(daiIn).to.be.bignumber.lt(daiInPreview.mul(new BN('10001')).div(new BN('10000')))
      })
    })

    describe('once mature', () => {
      beforeEach(async () => {
        await helper.advanceTime(31556952)
        await helper.advanceBlock()
        // await fyDai1.mature(); // It doesn't matter if the fyDai is marked as mature
      })

      it("doesn't allow trading", async () => {
        const oneToken = toWad(1)

        await expectRevert(pool.sellDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.sellDai(from, to, oneToken, { from: from }), 'Pool: Too late')
        await expectRevert(pool.buyDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.buyDai(from, to, oneToken, { from: from }), 'Pool: Too late')
        await expectRevert(pool.sellFYDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.sellFYDai(from, to, oneToken, { from: from }), 'Pool: Too late')
        await expectRevert(pool.buyFYDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.buyFYDai(from, to, oneToken, { from: from }), 'Pool: Too late')
      })
    })
  })
})
