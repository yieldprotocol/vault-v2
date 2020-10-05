const Test = artifacts.require('WhitepaperInvariantWrapper')
const YieldMath = artifacts.require('YieldMathMock')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { Contract } from '../shared/fixtures'
// @ts-ignore
import { BN } from '@openzeppelin/test-helpers'
import { expect } from 'chai'

contract('YieldMath - Reserves Value Invariant', async (accounts) => {
  let snapshot: any
  let snapshotId: string

  let test: Contract
  let yieldMath: Contract

  const b = new BN('18446744073709551615')
  const k = b.div(new BN('126144000'))
  const g1 = new BN('950').mul(b).div(new BN('1000')) // Sell Dai to the pool
  const g2 = new BN('1000').mul(b).div(new BN('950')) // Sell fyDai to the pool

  const values = [
    ['10000000000000000000000000', '20000000000000000000000000', '100000000000000000000', '10000000'],
    ['10000000000000000000000000', '20000000000000000000000000', '10000000000000000000000', '10000000'],
    ['10000000000000000000000000', '20000000000000000000000000', '1000000000000000000000000', '10000000'],
  ]

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    test = await Test.new()
    yieldMath = await YieldMath.new()
  })

  it('A lower g means more fees for `fyDaiOutForDaiIn`', async () => {
    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var fyDaiReserves = new BN(values[i][1])
      var daiIn = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var g = [
        ['1000', '1000'],
        ['990', '1000'],
        ['950', '1000'],
      ]

      let baseFYDaiOut = await yieldMath.fyDaiOutForDaiIn64(daiReserves, fyDaiReserves, daiIn, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', fyDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', daiIn.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())

      var previousFee = new BN('0')
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const fyDaiOut = await yieldMath.fyDaiOutForDaiIn64(daiReserves, fyDaiReserves, daiIn, timeTillMaturity, k, g_)
        const fee = baseFYDaiOut.sub(fyDaiOut)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
        expect(fee).to.be.bignumber.gte(previousFee)
      }
    }
  })

  it('A lower g means more fees for `daiInForFYDaiOut`', async () => {
    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var fyDaiReserves = new BN(values[i][1])
      var fyDaiOut = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var g = [
        ['1000', '1000'],
        ['990', '1000'],
        ['950', '1000'],
      ]

      let basfyDaiIn = await yieldMath.daiInForFYDaiOut64(daiReserves, fyDaiReserves, fyDaiOut, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', fyDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', fyDaiOut.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())

      var previousFee = new BN('0')
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const daiIn = await yieldMath.daiInForFYDaiOut64(daiReserves, fyDaiReserves, fyDaiOut, timeTillMaturity, k, g_)
        const fee = daiIn.sub(basfyDaiIn)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
        expect(fee).to.be.bignumber.gte(previousFee)
      }
    }
  })

  it('A higher g means more fees for `fyDaiInForDaiOut`', async () => {
    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var fyDaiReserves = new BN(values[i][1])
      var daiOut = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var g = [
        ['1000', '1000'],
        ['1000', '990'],
        ['1000', '950'],
      ]

      let baseFYDaiIn = await yieldMath.fyDaiInForDaiOut64(daiReserves, fyDaiReserves, daiOut, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', fyDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', daiOut.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())
      var previousFee = new BN('0')
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const fyDaiIn = await yieldMath.fyDaiInForDaiOut64(daiReserves, fyDaiReserves, daiOut, timeTillMaturity, k, g_)
        const fee = fyDaiIn.sub(baseFYDaiIn)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
        expect(fee).to.be.bignumber.gte(previousFee)
      }
    }
  })

  it('A higher g means more fees for `daiOutForFYDaiIn`', async () => {
    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var fyDaiReserves = new BN(values[i][1])
      var fyDaiIn = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var g = [
        ['1000', '1000'],
        ['1000', '990'],
        ['1000', '950'],
      ]

      let basfyDaiOut = await yieldMath.daiOutForFYDaiIn64(daiReserves, fyDaiReserves, fyDaiIn, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', fyDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', fyDaiIn.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())
      var previousFee = new BN('0')
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const daiOut = await yieldMath.daiOutForFYDaiIn64(daiReserves, fyDaiReserves, fyDaiIn, timeTillMaturity, k, g_)
        const fee = basfyDaiOut.sub(daiOut)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
        expect(fee).to.be.bignumber.gte(previousFee)
      }
    }
  })
})
