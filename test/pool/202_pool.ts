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
  const eDaiTokens1 = daiTokens1

  const oneToken = toWad(1)
  const initialDai = daiTokens1

  let snapshot: any
  let snapshotId: string

  let env: YieldEnvironmentLite

  let dai: Contract
  let pool: Contract
  let eDai1: Contract

  let maturity1: number

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup eDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952 // One year
    env = await YieldEnvironmentLite.setup([maturity1])
    dai = env.maker.dai
    eDai1 = env.eDais[0]

    // Setup Pool
    pool = await Pool.new(dai.address, eDai1.address, 'Name', 'Symbol', { from: owner })

    // Allow owner to mint eDai the sneaky way, without recording a debt in controller
    await eDai1.orchestrate(owner, keccak256(toUtf8Bytes('mint(address,uint256)')), { from: owner })
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
    const g2 = new BN('1000').mul(b).div(new BN('950')).add(new BN(1)) // Sell eDai to the pool
  })

  it('adds initial liquidity', async () => {
    await env.maker.getDai(user1, initialDai, rate1)

    console.log('        initial liquidity...')
    console.log('        daiReserves: %d', initialDai.toString())

    await dai.approve(pool.address, initialDai, { from: user1 })
    // await eDai1.approve(pool.address, eDaiTokens1, { from: user1 });
    const tx = await pool.init(initialDai, { from: user1 })
    const event = tx.logs[tx.logs.length - 1]

    assert.equal(event.event, 'Liquidity')
    assert.equal(event.args.from, user1)
    assert.equal(event.args.to, user1)
    assert.equal(event.args.daiTokens.toString(), initialDai.mul(-1).toString())
    assert.equal(event.args.eDaiTokens.toString(), 0)
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
      await pool.init(initialDai, { from: user1 })
    })

    it('sells eDai', async () => {
      const oneToken = toWad(1)
      await eDai1.mint(from, oneToken, { from: owner })

      // daiOutForEDaiIn formula: https://www.desmos.com/calculator/7knilsjycu

      console.log('          selling eDai...')
      console.log('          daiReserves: %d', await pool.getDaiReserves())
      console.log('          eDaiReserves: %d', await pool.getEDaiReserves())
      console.log('          eDaiIn: %d', oneToken.toString())
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
      const daiOutPreview = await pool.sellEDaiPreview(oneToken, { from: operator })

      await pool.addDelegate(operator, { from: from })
      await eDai1.approve(pool.address, oneToken, { from: from })
      const event = (await pool.sellEDai(from, to, oneToken, { from: operator })).logs[3]

      const expectedDaiOut = new BN(oneToken.toString()).mul(new BN('99732')).div(new BN('100000'))
      const daiOut = new BN(await dai.balanceOf(to))

      assert.equal(event.event, 'Trade')
      assert.equal(event.args.from, from)
      assert.equal(event.args.to, to)
      assert.equal(event.args.daiTokens, (await dai.balanceOf(to)).toString())
      assert.equal(event.args.eDaiTokens, oneToken.mul(-1).toString())

      assert.equal(await eDai1.balanceOf(from), 0, "'From' wallet should have no eDai tokens")

      expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.gt(daiOutPreview.mul(new BN('9999')).div(new BN('10000')))
      expect(daiOut).to.be.bignumber.lt(daiOutPreview.mul(new BN('10001')).div(new BN('10000')))
    })

    it('buys dai', async () => {
      const oneToken = toWad(1)
      await eDai1.mint(from, eDaiTokens1, { from: owner })

      // eDaiInForDaiOut formula: https://www.desmos.com/calculator/c1scsshbzh

      console.log('          buying dai...')
      console.log('          daiReserves: %d', await pool.getDaiReserves())
      console.log('          eDaiReserves: %d', await pool.getEDaiReserves())
      console.log('          daiOut: %d', oneToken.toString())
      console.log('          k: %d', await pool.k())
      console.log('          g2: %d', await pool.g2())
      const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
      console.log('          timeTillMaturity: %d', new BN(maturity1).sub(t).toString())

      assert.equal(
        await eDai1.balanceOf(from),
        eDaiTokens1.toString(),
        "'From' wallet should have " + eDaiTokens1 + ' eDai, instead has ' + (await eDai1.balanceOf(from))
      )

      // Test preview since we are here
      const eDaiInPreview = await pool.bueDaiPreview(oneToken, { from: operator })

      await pool.addDelegate(operator, { from: from })
      await eDai1.approve(pool.address, eDaiTokens1, { from: from })
      const event = (await pool.bueDai(from, to, oneToken, { from: operator })).logs[3]

      const expectedEDaiIn = new BN(oneToken.toString()).mul(new BN('100270')).div(new BN('100000'))
      const eDaiIn = new BN(eDaiTokens1.toString()).sub(new BN(await eDai1.balanceOf(from)))

      assert.equal(event.event, 'Trade')
      assert.equal(event.args.from, from)
      assert.equal(event.args.to, to)
      assert.equal(event.args.daiTokens, oneToken.toString())
      assert.equal(event.args.eDaiTokens, eDaiIn.mul(new BN('-1')).toString())

      assert.equal(await dai.balanceOf(to), oneToken.toString(), 'Receiver account should have 1 dai token')

      expect(eDaiIn).to.be.bignumber.gt(expectedEDaiIn.mul(new BN('9999')).div(new BN('10000')))
      expect(eDaiIn).to.be.bignumber.lt(expectedEDaiIn.mul(new BN('10001')).div(new BN('10000')))
      expect(eDaiIn).to.be.bignumber.gt(eDaiInPreview.mul(new BN('9999')).div(new BN('10000')))
      expect(eDaiIn).to.be.bignumber.lt(eDaiInPreview.mul(new BN('10001')).div(new BN('10000')))
    })

    describe('with extra eDai reserves', () => {
      beforeEach(async () => {
        const additionalEDaiReserves = toWad(34.4)
        await eDai1.mint(operator, additionalEDaiReserves, { from: owner })
        await eDai1.approve(pool.address, additionalEDaiReserves, { from: operator })
        await pool.sellEDai(operator, operator, additionalEDaiReserves, { from: operator })
      })

      it('mints liquidity tokens', async () => {
        // Use this to test: https://www.desmos.com/calculator/mllhtohxfx

        console.log('          minting liquidity tokens...')
        console.log('          Real daiReserves: %d', await dai.balanceOf(pool.address))
        console.log('          Real eDaiReserves: %d', await eDai1.balanceOf(pool.address))
        console.log('          Pool supply: %d', await pool.totalSupply())
        console.log('          daiIn: %d', oneToken.toString())

        await dai.mint(user1, oneToken, { from: owner }) // Not feeling like fighting with Vat
        await eDai1.mint(user1, eDaiTokens1, { from: owner })

        const eDaiBefore = new BN(await eDai1.balanceOf(user1))
        const poolTokensBefore = new BN(await pool.balanceOf(user2))

        await dai.approve(pool.address, oneToken, { from: user1 })
        await eDai1.approve(pool.address, eDaiTokens1, { from: user1 })
        const tx = await pool.mint(user1, user2, oneToken, { from: user1 })
        const event = tx.logs[tx.logs.length - 1]

        const expectedMinted = new BN('1473236946700000000')
        const expectedEDaiIn = new BN('517558731280000000')

        const minted = new BN(await pool.balanceOf(user2)).sub(poolTokensBefore)
        const eDaiIn = eDaiBefore.sub(new BN(await eDai1.balanceOf(user1)))

        assert.equal(event.event, 'Liquidity')
        assert.equal(event.args.from, user1)
        assert.equal(event.args.to, user2)
        assert.equal(event.args.daiTokens, oneToken.mul(-1).toString())

        expect(minted).to.be.bignumber.gt(expectedMinted.mul(new BN('9999')).div(new BN('10000')))
        expect(minted).to.be.bignumber.lt(expectedMinted.mul(new BN('10001')).div(new BN('10000')))

        expect(eDaiIn).to.be.bignumber.gt(expectedEDaiIn.mul(new BN('9999')).div(new BN('10000')))
        expect(eDaiIn).to.be.bignumber.lt(expectedEDaiIn.mul(new BN('10001')).div(new BN('10000')))

        assert.equal(event.args.eDaiTokens, eDaiIn.mul(new BN('-1')).toString())
        assert.equal(event.args.poolTokens, minted.toString())
      })

      it('burns liquidity tokens', async () => {
        // Use this to test: https://www.desmos.com/calculator/ubsalzunpo

        console.log('          burning liquidity tokens...')
        console.log('          Real daiReserves: %d', await dai.balanceOf(pool.address))
        console.log('          Real eDaiReserves: %d', await eDai1.balanceOf(pool.address))
        console.log('          Pool supply: %d', await pool.totalSupply())
        console.log('          Burned: %d', oneToken.toString())

        const eDaiReservesBefore = new BN(await eDai1.balanceOf(pool.address))
        const daiReservesBefore = new BN(await dai.balanceOf(pool.address))

        await pool.approve(pool.address, oneToken, { from: user1 })
        const tx = await pool.burn(user1, user2, oneToken, { from: user1 })
        const event = tx.logs[tx.logs.length - 1]

        const expectedEDaiOut = new BN('351307189540000000')
        const expectedDaiOut = new BN('678777437820000000')

        const eDaiOut = eDaiReservesBefore.sub(new BN(await eDai1.balanceOf(pool.address)))
        const daiOut = daiReservesBefore.sub(new BN(await dai.balanceOf(pool.address)))

        assert.equal(event.event, 'Liquidity')
        assert.equal(event.args.from, user1)
        assert.equal(event.args.to, user2)
        assert.equal(event.args.poolTokens, oneToken.mul(-1).toString())

        expect(eDaiOut).to.be.bignumber.gt(expectedEDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(eDaiOut).to.be.bignumber.lt(expectedEDaiOut.mul(new BN('10001')).div(new BN('10000')))

        expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')))

        assert.equal(event.args.eDaiTokens, eDaiOut.toString())
        assert.equal(event.args.daiTokens, daiOut.toString())
      })

      it('sells dai', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // eDaiOutForDaiIn formula: https://www.desmos.com/calculator/8eczy19er3

        console.log('          selling dai...')
        console.log('          daiReserves: %d', await pool.getDaiReserves())
        console.log('          eDaiReserves: %d', await pool.getEDaiReserves())
        console.log('          daiIn: %d', oneToken.toString())
        console.log('          k: %d', await pool.k())
        console.log('          g1: %d', await pool.g1())
        const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
        console.log('          timeTillMaturity: %d', new BN(maturity1).sub(t).toString())

        assert.equal(
          await eDai1.balanceOf(to),
          0,
          "'To' wallet should have no eDai, instead has " + (await eDai1.balanceOf(operator))
        )

        // Test preview since we are here
        const eDaiOutPreview = await pool.sellDaiPreview(oneToken, { from: operator })

        await pool.addDelegate(operator, { from: from })
        await dai.approve(pool.address, oneToken, { from: from })
        const event = (await pool.sellDai(from, to, oneToken, { from: operator })).logs[2]

        const expectedEDaiOut = new BN(oneToken.toString()).mul(new BN('117440')).div(new BN('100000'))
        const eDaiOut = new BN(await eDai1.balanceOf(to))

        assert.equal(event.event, 'Trade')
        assert.equal(event.args.from, from)
        assert.equal(event.args.to, to)
        assert.equal(event.args.daiTokens, oneToken.mul(-1).toString())
        assert.equal(event.args.eDaiTokens, eDaiOut.toString())

        assert.equal(
          await dai.balanceOf(from),
          daiTokens1.sub(oneToken).toString(),
          "'From' wallet should have " + daiTokens1.sub(oneToken) + ' dai tokens'
        )

        expect(eDaiOut).to.be.bignumber.gt(expectedEDaiOut.mul(new BN('9999')).div(new BN('10000')))
        expect(eDaiOut).to.be.bignumber.lt(expectedEDaiOut.mul(new BN('10001')).div(new BN('10000')))
        expect(eDaiOut).to.be.bignumber.gt(eDaiOutPreview.mul(new BN('9999')).div(new BN('10000')))
        expect(eDaiOut).to.be.bignumber.lt(eDaiOutPreview.mul(new BN('10001')).div(new BN('10000')))
      })

      it('buys eDai', async () => {
        const oneToken = toWad(1)
        await env.maker.getDai(from, daiTokens1, rate1)

        // daiInForEDaiOut formula: https://www.desmos.com/calculator/grjod0grzp

        console.log('          buying eDai...')
        console.log('          daiReserves: %d', await pool.getDaiReserves())
        console.log('          eDaiReserves: %d', await pool.getEDaiReserves())
        console.log('          eDaiOut: %d', oneToken.toString())
        console.log('          k: %d', await pool.k())
        console.log('          g1: %d', await pool.g1())
        const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
        console.log('          timeTillMaturity: %d', new BN(maturity1).sub(t).toString())

        assert.equal(
          await eDai1.balanceOf(to),
          0,
          "'To' wallet should have no eDai, instead has " + (await eDai1.balanceOf(to))
        )

        // Test preview since we are here
        const daiInPreview = await pool.buyEDaiPreview(oneToken, { from: operator })

        await pool.addDelegate(operator, { from: from })
        await dai.approve(pool.address, daiTokens1, { from: from })
        const event = (await pool.buyEDai(from, to, oneToken, { from: operator })).logs[2]

        const expectedDaiIn = new BN(oneToken.toString()).mul(new BN('85110')).div(new BN('100000'))
        const daiIn = new BN(daiTokens1.toString()).sub(new BN(await dai.balanceOf(from)))

        assert.equal(event.event, 'Trade')
        assert.equal(event.args.from, from)
        assert.equal(event.args.to, to)
        assert.equal(event.args.daiTokens, daiIn.mul(new BN('-1')).toString())
        assert.equal(event.args.eDaiTokens, oneToken.toString())

        assert.equal(await eDai1.balanceOf(to), oneToken.toString(), "'To' wallet should have 1 eDai token")

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
        // await eDai1.mature(); // It doesn't matter if the eDai is marked as mature
      })

      it("doesn't allow trading", async () => {
        const oneToken = toWad(1)

        await expectRevert(pool.sellDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.sellDai(from, to, oneToken, { from: from }), 'Pool: Too late')
        await expectRevert(pool.bueDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.bueDai(from, to, oneToken, { from: from }), 'Pool: Too late')
        await expectRevert(pool.sellEDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.sellEDai(from, to, oneToken, { from: from }), 'Pool: Too late')
        await expectRevert(pool.buyEDaiPreview(oneToken, { from: operator }), 'Pool: Too late')
        await expectRevert(pool.buyEDai(from, to, oneToken, { from: from }), 'Pool: Too late')
      })
    })
  })
})
