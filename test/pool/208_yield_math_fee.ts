const Test = artifacts.require('WhitepaperInvariantWrapper')
const YieldMath = artifacts.require('YieldMathMock')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { Contract } from '../shared/fixtures'
// @ts-ignore
import { BN } from '@openzeppelin/test-helpers'

contract('YieldMath - Reserves Value Invariant', async (accounts) => {
  let snapshot: any
  let snapshotId: string

  let test: Contract
  let yieldMath: Contract

  const b = new BN('18446744073709551615')
  const k = b.div(new BN('126144000'))
  const g1 = new BN('950').mul(b).div(new BN('1000')) // Sell Dai to the pool
  const g2 = new BN('1000').mul(b).div(new BN('950')) // Sell eDai to the pool

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    test = await Test.new()
    yieldMath = await YieldMath.new()
  })

  it('A lower g means more fees for `eDaiOutForDaiIn`', async () => {
    var values = [
      ['10000000000000000000000000', '20000000000000000000000000', '100000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '10000000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '1000000000000000000000000', '10000000'],
    ]

    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var eDaiReserves = new BN(values[i][1])
      var daiIn = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = [
        ['1000', '1000'],
        ['990', '1000'],
        ['950', '1000'],
      ]

      let baseEDaiOut = await yieldMath.eDaiOutForDaiIn64(daiReserves, eDaiReserves, daiIn, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', eDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', daiIn.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const eDaiOut = await yieldMath.eDaiOutForDaiIn64(daiReserves, eDaiReserves, daiIn, timeTillMaturity, k, g_)
        const fee = baseEDaiOut.sub(eDaiOut)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
      }

      // expect(result[1]).to.be.bignumber.gt(previousResult.toString())
    }
  })

  it('A lower g means more fees for `daiInForEDaiOut`', async () => {
    var values = [
      ['10000000000000000000000000', '20000000000000000000000000', '100000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '10000000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '1000000000000000000000000', '10000000'],
    ]

    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var eDaiReserves = new BN(values[i][1])
      var eDaiOut = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = [
        ['1000', '1000'],
        ['990', '1000'],
        ['950', '1000'],
      ]

      let baseDaiIn = await yieldMath.daiInForEDaiOut64(daiReserves, eDaiReserves, eDaiOut, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', eDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', eDaiOut.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const daiIn = await yieldMath.daiInForEDaiOut64(daiReserves, eDaiReserves, eDaiOut, timeTillMaturity, k, g_)
        const fee = daiIn.sub(baseDaiIn)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
      }

      // expect(result[1]).to.be.bignumber.gt(previousResult.toString())
    }
  })

  it('A higher g means more fees for `eDaiInForDaiOut`', async () => {
    var values = [
      ['10000000000000000000000000', '20000000000000000000000000', '100000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '10000000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '1000000000000000000000000', '10000000'],
    ]

    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var eDaiReserves = new BN(values[i][1])
      var daiOut = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = [
        ['1000', '1000'],
        ['1000', '990'],
        ['1000', '950'],
      ]

      let baseEDaiIn = await yieldMath.eDaiInForDaiOut64(daiReserves, eDaiReserves, daiOut, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', eDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', daiOut.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const eDaiIn = await yieldMath.eDaiInForDaiOut64(daiReserves, eDaiReserves, daiOut, timeTillMaturity, k, g_)
        const fee = eDaiIn.sub(baseEDaiIn)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
      }

      // expect(result[1]).to.be.bignumber.gt(previousResult.toString())
    }
  })

  it('A higher g means more fees for `daiOutForEDaiIn`', async () => {
    var values = [
      ['10000000000000000000000000', '20000000000000000000000000', '100000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '10000000000000000000000', '10000000'],
      ['10000000000000000000000000', '20000000000000000000000000', '1000000000000000000000000', '10000000'],
    ]

    for (var i = 0; i < values.length; i++) {
      var daiReserves = new BN(values[i][0])
      var eDaiReserves = new BN(values[i][1])
      var eDaiIn = new BN(values[i][2])
      var timeTillMaturity = new BN(values[i][3])
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = [
        ['1000', '1000'],
        ['1000', '990'],
        ['1000', '950'],
      ]

      let baseDaiOut = await yieldMath.daiOutForEDaiIn64(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity, k, b)
      console.log('')
      console.log('      Z: $%dMM', daiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      Y: $%dMM', eDaiReserves.div(new BN('1000000000000000000000000')).toString())
      console.log('      x: $%d', eDaiIn.div(new BN('1000000000000000000')).toString())
      console.log('      t: %d', timeTillMaturity.toString())
      for (var j = 0; j < g.length; j++) {
        var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
        const daiOut = await yieldMath.daiOutForEDaiIn64(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity, k, g_)
        const fee = baseDaiOut.sub(daiOut)
        console.log('      %d/%d: %d¢', g[j][0], g[j][1], fee.div(new BN('10000000000000000')).toString())
      }

      // expect(result[1]).to.be.bignumber.gt(previousResult.toString())
    }
  })
})
