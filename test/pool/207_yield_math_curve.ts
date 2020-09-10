const YieldMath = artifacts.require('YieldMathWrapper')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { Contract } from '../shared/fixtures'
// @ts-ignore
import { BN } from '@openzeppelin/test-helpers'
import { expect } from 'chai'

/**
 * Throws given message unless given condition is true.
 *
 * @param message message to throw unless given condition is true
 * @param condition condition to check
 */
function assert(message: string, condition: boolean) {
  if (!condition) throw message
}

function toBigNumber(x: any) {
  if (typeof x == 'object') x = x.toString()
  if (typeof x == 'number') return new BN(x)
  else if (typeof x == 'string') {
    if (x.startsWith('0x') || x.startsWith('0X')) return new BN(x.substring(2), 16)
    else return new BN(x)
  }
}

contract('YieldMath - Curve', async (accounts) => {
  let snapshot: any
  let snapshotId: string

  let yieldMath: Contract

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    yieldMath = await YieldMath.new()
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  describe('Test trading functions', async () => {
    it('A higher g means more yDai out with `yDaiOutForDaiIn`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]

      for (var i = 0; i < values.length; i++) {
        // for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var b = new BN('18446744073709551615')
        var k = b.div(new BN('126144000'))
        var g = [
          ['9', '10'],
          ['95', '100'],
          ['950', '1000'],
        ]
        var previousResult = new BN('0')
        for (var j = 0; j < g.length; j++) {
          var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
          var result
          try {
            result = await yieldMath.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g_)
          } catch (e) {
            result = [false, undefined]
          }
        }

        expect(result[1]).to.be.bignumber.gt(previousResult.toString())
        previousResult = result[1]
      }
    })

    it('As we approach maturity, price grows to 1 for `yDaiOutForDaiIn`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]
      var timeTillMaturity = ['0', '40', '4000', '400000', '40000000']
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = new BN('950').mul(b).div(new BN('1000'))

      for (var i = 0; i < values.length; i++) {
        // console.log("")
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)

        const flatFee = new BN('1000000000000')
        const maximum = daiAmount.sub(flatFee)
        var previousResult = maximum
        for (var j = 0; j < timeTillMaturity.length; j++) {
          var t = timeTillMaturity[j]

          var result
          try {
            result = await yieldMath.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, t, k, g)
          } catch (e) {
            result = [false, undefined]
          }

          // console.log("      " + result[1].toString())
          if (j == 0) {
            // Test that when we are very close to maturity, price is very close to 1 minus flat fee.
            expect(result[1]).to.be.bignumber.lt(maximum.mul(new BN('1000000')).div(new BN('999999')).toString())
            expect(result[1]).to.be.bignumber.gt(maximum.mul(new BN('999999')).div(new BN('1000000')).toString())
          } else {
            // Easier to test prices diverging from 1
            expect(result[1]).to.be.bignumber.lt(previousResult.toString())
          }
          previousResult = result[1]
        }
      }
    })

    it('A lower g means more Dai out with `daiOutForYDaiIn`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]

      for (var i = 0; i < values.length; i++) {
        // for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var b = new BN('18446744073709551615')
        var k = b.div(new BN('126144000'))
        var g = [
          ['950', '1000'],
          ['95', '100'],
          ['9', '10'],
        ]
        var previousResult = new BN('0')
        for (var j = 0; j < g.length; j++) {
          var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
          var result
          try {
            result = await yieldMath.daiOutForYDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g_)
          } catch (e) {
            result = [false, undefined]
          }
        }

        expect(result[1]).to.be.bignumber.gt(previousResult.toString())
        previousResult = result[1]
      }
    })

    it('As we approach maturity, price drops to 1 for `daiOutForYDaiIn`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]
      var timeTillMaturity = ['0', '40', '4000', '400000', '40000000']
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = new BN('1000').mul(b).div(new BN('950'))

      for (var i = 0; i < values.length; i++) {
        // console.log("")
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)

        const flatFee = new BN('1000000000000')
        const minimum = daiAmount.sub(flatFee)
        var previousResult = minimum
        for (var j = 0; j < timeTillMaturity.length; j++) {
          var t = timeTillMaturity[j]

          var result
          try {
            result = await yieldMath.daiOutForYDaiIn(daiReserves, yDAIReserves, daiAmount, t, k, g)
          } catch (e) {
            result = [false, undefined]
          }

          // console.log("      " + result[1].toString())
          if (j == 0) {
            // Test that when we are very close to maturity, price is very close to 1 minus flat fee.
            expect(result[1]).to.be.bignumber.gt(minimum.mul(new BN('999999')).div(new BN('1000000')).toString())
            expect(result[1]).to.be.bignumber.lt(minimum.mul(new BN('1000000')).div(new BN('999999')).toString())
          } else {
            // Easier to test prices diverging from 1
            expect(result[1]).to.be.bignumber.gt(previousResult.toString())
          }
          previousResult = result[1]
        }
      }
    })

    it('A higher g means more yDai in with `yDaiInForDaiOut`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]

      for (var i = 0; i < values.length; i++) {
        // for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var b = new BN('18446744073709551615')
        var k = b.div(new BN('126144000'))
        var g = [
          ['9', '10'],
          ['95', '100'],
          ['950', '1000'],
        ]
        var previousResult = new BN('0')
        for (var j = 0; j < g.length; j++) {
          var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
          var result
          try {
            result = await yieldMath.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g_)
          } catch (e) {
            result = [false, undefined]
          }
        }

        expect(result[1]).to.be.bignumber.gt(previousResult.toString())
        previousResult = result[1]
      }
    })

    it('As we approach maturity, price grows to 1 for `yDaiInForDaiOut`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]
      var timeTillMaturity = ['0', '40', '4000', '400000', '40000000']
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = new BN('1000').mul(b).div(new BN('950'))

      for (var i = 0; i < values.length; i++) {
        // console.log("")
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)

        const flatFee = new BN('1000000000000')
        const maximum = daiAmount.add(flatFee)
        var previousResult = maximum
        for (var j = 0; j < timeTillMaturity.length; j++) {
          var t = timeTillMaturity[j]

          var result
          try {
            result = await yieldMath.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, t, k, g)
          } catch (e) {
            result = [false, undefined]
          }

          // console.log("      " + result[1].toString())
          if (j == 0) {
            // Test that when we are very close to maturity, price is very close to 1 plus flat fee.
            expect(result[1]).to.be.bignumber.lt(maximum.mul(new BN('1000000')).div(new BN('999999')).toString())
            expect(result[1]).to.be.bignumber.gt(maximum.mul(new BN('999999')).div(new BN('1000000')).toString())
          } else {
            // Easier to test prices diverging from 1
            expect(result[1]).to.be.bignumber.lt(previousResult.toString())
          }
          previousResult = result[1]
        }
      }
    })

    it('A lower g means more Dai in with `daiInForYDaiOut`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]

      for (var i = 0; i < values.length; i++) {
        // for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var b = new BN('18446744073709551615')
        var k = b.div(new BN('126144000'))
        var g = [
          ['950', '1000'],
          ['95', '100'],
          ['9', '10'],
        ]
        var previousResult = new BN('0')
        for (var j = 0; j < g.length; j++) {
          var g_ = new BN(g[j][0]).mul(b).div(new BN(g[j][1]))
          var result
          try {
            result = await yieldMath.daiInForYDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g_)
          } catch (e) {
            result = [false, undefined]
          }
        }

        expect(result[1]).to.be.bignumber.gt(previousResult.toString())
        previousResult = result[1]
      }
    })

    it('As we approach maturity, price drops to 1 for `daiInForYDaiOut`', async () => {
      var values = [
        ['10000000000000000000000', '1000000000000000000000', '10000000000000000000', '1000000'],
        ['100000000000000000000000000', '10000000000000000000000000', '1000000000000000000000', '1000000'],
        ['1000000000000000000000000000000', '100000000000000000000000000000', '100000000000000000000000', '1000000'],
      ]
      var timeTillMaturity = ['0', '40', '4000', '400000', '40000000']
      var b = new BN('18446744073709551615')
      var k = b.div(new BN('126144000'))
      var g = new BN('950').mul(b).div(new BN('1000'))

      for (var i = 0; i < values.length; i++) {
        // console.log("")
        var daiReservesValue = values[i][0]
        var yDAIReservesValue = values[i][1]
        var daiAmountValue = values[i][2]

        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)

        const flatFee = new BN('1000000000000')
        const minimum = daiAmount.add(flatFee)
        var previousResult = minimum
        for (var j = 0; j < timeTillMaturity.length; j++) {
          var t = timeTillMaturity[j]

          var result
          try {
            result = await yieldMath.daiInForYDaiOut(daiReserves, yDAIReserves, daiAmount, t, k, g)
          } catch (e) {
            result = [false, undefined]
          }

          // console.log("      " + result[1].toString())
          if (j == 0) {
            // Test that when we are very close to maturity, price is very close to 1 plus flat fee.
            expect(result[1]).to.be.bignumber.gt(minimum.mul(new BN('999999')).div(new BN('1000000')).toString())
            expect(result[1]).to.be.bignumber.lt(minimum.mul(new BN('1000000')).div(new BN('999999')).toString())
          } else {
            // Easier to test prices diverging from 1
            expect(result[1]).to.be.bignumber.gt(previousResult.toString())
          }
          previousResult = result[1]
        }
      }
    })
  })
})
