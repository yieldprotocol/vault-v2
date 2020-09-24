const YieldMath = artifacts.require('YieldMathWrapper')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'

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

contract('YieldMath - Base', async (accounts) => {
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

  it('get the size of the contract', async () => {
    console.log()
    console.log('    ·--------------------|------------------|------------------|------------------·')
    console.log('    |  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |')
    console.log('    ·····················|··················|··················|···················')

    const bytecode = yieldMath.constructor._json.bytecode
    const deployed = yieldMath.constructor._json.deployedBytecode
    const sizeOfB = bytecode.length / 2
    const sizeOfD = deployed.length / 2
    const sizeOfC = sizeOfB - sizeOfD
    console.log(
      '    |  ' +
        yieldMath.constructor._json.contractName.padEnd(18, ' ') +
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

  describe('Test pure math functions', async () => {
    it('Test `log_2` function', async () => {
      var xValues = [
        '0x0',
        '0x1',
        '0x2',
        '0xFEDCBA9876543210',
        '0xFFFFFFFFFFFFFFFF',
        '0x10000000000000000',
        '0xFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x1000000000000000000000000',
        '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x10000000000000000000000000000',
        '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x1000000000000000000000000000000',
        '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x10000000000000000000000000000000',
        '0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x40000000000000000000000000000000',
        '0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x80000000000000000000000000000000',
        '0xFEDCBA9876543210FEDCBA9876543210',
        '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
      ]

      for (var i = 0; i < xValues.length; i++) {
        var xValue = xValues[i]
        // console.log('    log_2 (' + xValue + ')')
        var x = toBigNumber(xValue)
        var result
        try {
          result = await yieldMath.log_2(x)
        } catch (e) {
          result = [false, undefined]
        }
        if (!x.eq(toBigNumber('0x0'))) {
          assert('log_2 (' + xValue + ')[0]', result[0])
          assert(
            'log_2 (' + xValue + ')[1]',
            Math.abs(
              Math.log(Number(x)) / Math.LN2 -
                Number(result[1]) / Number(toBigNumber('0x2000000000000000000000000000000'))
            ) < 0.00000000001
          )
        } else {
          assert('!log_2 (' + xValue + ')[0]', !result[0])
        }
      }
    })

    it('Test `pow_2` function', async () => {
      var xValues = [
        '0x0',
        '0x1',
        '0x2',
        '0x1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x2000000000000000000000000000000',
        '0x2000000000000000000000000000001',
        '0x20123456789ABCDEF0123456789ABCD',
        '0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x40000000000000000000000000000000',
        '0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        '0x80000000000000000000000000000000',
        '0xFEDCBA9876543210FEDCBA9876543210',
        '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
      ]

      for (var i = 0; i < xValues.length; i++) {
        var xValue = xValues[i]
        // console.log('    pow_2 (' + xValue + ')')
        var x = toBigNumber(xValue)
        var result
        try {
          result = await yieldMath.pow_2(x)
        } catch (e) {
          result = [false, undefined]
        }
        assert('pow_2 (' + xValue + ')[0]', result[0])
        var expected = Math.pow(2, Number(x) / Number(toBigNumber('0x2000000000000000000000000000000')))
        assert(
          'pow_2 (' + xValue + ')[1]',
          Math.abs(expected - Number(result[1])) <= Math.max(1.0000000000001, expected / 1000000000000.0)
        )
      }
    })

    it('Test `pow` function', async () => {
      var xValues = ['0x0', '0x1', '0x2', '0xFEDCBA9876543210', '0xFEDCBA9876543210FEDCBA9876543210']
      var yzValues = [
        ['0x0', '0x0'],
        ['0x1', '0x0'],
        ['0x0', '0x1'],
        ['0x1', '0x1'],
        ['0x2', '0x1'],
        ['0x3', '0x1'],
        ['0x7F', '0x1'],
        ['0xFEDCBA987', '0x1'],
        ['0xFEDCBA9876543210FEDCBA9876543210', '0x1'],
        ['0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', '0x1'],
        ['0x1', '0x2'],
        ['0x1', '0x3'],
        ['0x1', '0x7F'],
        ['0x1', '0xFEDCBA9876543210'],
        ['0x1', '0xFEDCBA9876543210FEDCBA9876543210'],
        ['0x1', '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'],
      ]

      for (var i = 0; i < xValues.length; i++) {
        var xValue = xValues[i]
        for (var j = 0; j < yzValues.length; j++) {
          var yValue = yzValues[j][0]
          var zValue = yzValues[j][1]
          // console.log('    pow (' + xValue + ', ' + yValue + ', ' + zValue + ')')
          var x = toBigNumber(xValue)
          var y = toBigNumber(yValue)
          var z = toBigNumber(zValue)
          var result
          try {
            result = await yieldMath.pow(x, y, z)
          } catch (e) {
            result = [false, undefined]
          }

          if (!z.eq(toBigNumber('0x0')) && (!x.eq(toBigNumber('0x0')) || !y.eq(toBigNumber('0x0')))) {
            assert('pow (' + xValue + ', ' + yValue + ', ' + zValue + ')[0]', result[0])
            var expectedLog =
              (Math.log(Number(x)) * Number(y)) / Number(z) + 128 * (1.0 - Number(y) / Number(z)) * Math.LN2
            if (expectedLog < 0.0) expectedLog = -1.0
            if (x.eq(toBigNumber('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'))) expectedLog = 128 * Math.LN2
            var resultLog = Math.log(Number(result[1]))
            if (resultLog < 0.0) resultLog = -1.0
            assert(
              'pow (' + xValue + ', ' + yValue + ', ' + zValue + ')[1]',
              Math.abs(expectedLog - resultLog) <= 0.000000001
            )
          } else {
            assert('!pow (' + xValue + ', ' + yValue + ', ' + zValue + ')[0]', !result[0])
          }
        }
      }
    })
  })

  describe('Test trading functions', async () => {
    var timeTillMaturityValues = ['0x0', '0xf', '0xff', '0xfff', '0xffff', '0xfffff', '0xffffff', '0x784ce00']
    var daiReserveValues = [
      '0x52b7d2dcc80cd2e4000000',
      '0xa56fa5b99019a5c8000000',
      '0x14adf4b7320334b90000000',
      '0x295be96e640669720000000',
    ]
    var eDaiReserveValues = [
      '0x52b7d2dcc80cd2e4000001',
      '0xa56fa5b99019a5c8000001',
      '0x14adf4b7320334b90000001',
      '0x295be96e640669720000001',
    ]

    it('Test `eDaiOutForDaiIn` function', async () => {
      var values = [
        ['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x0', '0x1', '0xFFFFFFFFFFFFFFFF', '0x10000000000000000', true, 0.0],
        ['0x0', '0x0', '0x0', '0x1', '0x10000000000000000', '0x10000000000000000', false],
        ['0x80000000000000000000000000000000', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        ['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        ['0x0', '0x80000000000000000000000000000000', '0x80000000000000000000000000000000', '0x0', '0x0', '0x0', true],
        ['0x0', '0x80000000000000000000000000000000', '0x8000000002000000000000000000000D', '0x0', '0x0', '0x0', false],
        [
          '0xFEDCBA9876543210',
          '0x123456789ABCDEF0',
          '0x123456789ABC',
          '0x1',
          '0x8000000000000000',
          '0xFEDCBA9876543210',
          true,
        ],
        // Use this to debug
        /* [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xf333333333333333',   // g = 950 / 1000 in 64.64
          true,                   // ?
        ], */
      ]

      for (var i = 0; i < values.length; i++) {
        // for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var eDaiReservesValue = values[i][1]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /* console.log(
          '    eDaiOutForDaiIn (' +
            daiReservesValue +
            ', ' +
            eDaiReservesValue +
            ', ' +
            daiAmountValue +
            ', ' +
            timeTillMaturityValue +
            ', ' +
            kValue +
            ', ' +
            gValue +
            ')'
        ) */
        var daiReserves = toBigNumber(daiReservesValue)
        var eDaiReserves = toBigNumber(eDaiReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.eDaiOutForDaiIn(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }

        /* console.log(
          '    eDaiOutForDaiIn (' +
            daiReserves.toString() +
            ', ' +
            eDaiReserves.toString() +
            ', ' +
            daiAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        ) */

        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
        var fee = Number(toBigNumber('1000000000000'))

        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Number(eDaiReserves) -
              Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(eDaiReserves), a) -
                  Math.pow(Number(daiReserves.add(daiAmount)), a),
                1.0 / a
              ) -
              fee
        expected = expected < 0 ? 0 : expected // Floor at zero

        if (values[i][6]) {
          assert(
            'eDaiOutForDaiIn (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              daiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            result[0]
          )
          assert(
            'eDaiOutForDaiIn (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              daiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[1]',
            Math.abs(expected - Number(result[1])) <= Math.max(0.000001, expected / 100000.0)
          )
        } else {
          assert(
            '!eDaiOutForDaiIn (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              daiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            !result[0]
          )
        }
      }
    })

    it('Test `daiOutForEDaiIn` function', async () => {
      var values = [
        ['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x0', '0x1', '0xFFFFFFFFFFFFFFFF', '0x10000000000000000', true, 0.0],
        ['0x0', '0x0', '0x0', '0x1', '0x10000000000000000', '0x10000000000000000', false],
        ['0x0', '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', '0x1', '0x0', '0x0', '0x0', false],
        ['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        ['0x80000000000000000000000000000000', '0x0', '0x80000000000000000000000000000000', '0x0', '0x0', '0x0', true],
        ['0x80000000000000000000000000000000', '0x0', '0x8000000002000000000000000000000D', '0x0', '0x0', '0x0', false],
        [
          '0xFEDCBA9876543210',
          '0x123456789ABCDEF0',
          '0x123456789ABC',
          '0x1',
          '0x8000000000000000',
          '0xFEDCBA9876543210',
          true,
        ],
        // Use this to debug
        /* [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xf333333333333333',   // g = 950 / 1000 in 64.64
          true,                   // ?
        ], */
      ]

      for (var i = 0; i < values.length; i++) {
        //for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var eDaiReservesValue = values[i][1]
        var eDaiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /* console.log(
          '    daiOutForEDaiIn (' +
            daiReservesValue +
            ', ' +
            eDaiReservesValue +
            ', ' +
            eDaiAmountValue +
            ', ' +
            timeTillMaturityValue +
            ', ' +
            kValue +
            ', ' +
            gValue +
            ')'
        ) */
        var daiReserves = toBigNumber(daiReservesValue)
        var eDaiReserves = toBigNumber(eDaiReservesValue)
        var eDaiAmount = toBigNumber(eDaiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.daiOutForEDaiIn(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }

        /* console.log(
          '    daiOutForEDaiIn (' +
            daiReserves.toString() +
            ', ' +
            eDaiReserves.toString() +
            ', ' +
            eDaiAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        ) */

        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
        var fee = Number(toBigNumber('1000000000000'))

        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Number(daiReserves) -
              Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(eDaiReserves), a) -
                  Math.pow(Number(eDaiReserves.add(eDaiAmount)), a),
                1.0 / a
              ) -
              fee
        expected = expected < 0 ? 0 : expected // Floor at zero

        if (values[i][6]) {
          assert(
            'daiOutForEDaiIn (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              eDaiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            result[0]
          )
          assert(
            'daiOutForEDaiIn (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              eDaiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[1]',
            Math.abs(expected - Number(result[1])) <= Math.max(0.000001, expected / 100000.0)
          )
        } else {
          assert(
            '!daiOutForEDaiIn (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              eDaiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            !result[0]
          )
        }
      }
    })

    it('Test `eDaiInForDaiOut` function', async () => {
      var values = [
        ['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        // ['0x0', '0x0', '0x0', '0x1', '0xFFFFFFFFFFFFFFFF', '0x10000000000000000', true, 0.0], // Testing too far from reality
        ['0x0', '0x0', '0x0', '0x1', '0x10000000000000000', '0x10000000000000000', false],
        ['0x80000000000000000000000000000000', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        [
          '0x80000000000000000000000000000000',
          '0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
          '0x80000000000000000000000000000000',
          '0x0',
          '0x0',
          '0x0',
          true,
        ],
        [
          '0x80000000000000000000000000000000',
          '0x80000000000000000000000000000000',
          '0x80000000000000000000000000000000',
          '0x0',
          '0x0',
          '0x0',
          false,
        ],
        [
          '0xFEDCBA9876543210',
          '0x123456789ABCDEF0',
          '0x123456789ABC',
          '0x1',
          '0x8000000000000000',
          '0xFEDCBA9876543210',
          true,
        ],
        // Use this to debug
        /* [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xf333333333333333',   // g = 950 / 1000 in 64.64
          true,                   // ?
        ], */
      ]

      for (var i = 0; i < values.length; i++) {
        // for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var eDaiReservesValue = values[i][1]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /* console.log(
          '    eDaiInForDaiOut (' +
            daiReservesValue +
            ', ' +
            eDaiReservesValue +
            ', ' +
            daiAmountValue +
            ', ' +
            timeTillMaturityValue +
            ', ' +
            kValue +
            ', ' +
            gValue +
            ')'
        ) */
        var daiReserves = toBigNumber(daiReservesValue)
        var eDaiReserves = toBigNumber(eDaiReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.eDaiInForDaiOut(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }

        /* console.log(
          '    eDaiInForDaiOut (' +
            daiReserves.toString() +
            ', ' +
            eDaiReserves.toString() +
            ', ' +
            daiAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        ) */

        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
        var fee = Number(toBigNumber('1000000000000'))

        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(eDaiReserves), a) -
                  Math.pow(Number(daiReserves.sub(daiAmount)), a),
                1.0 / a
              ) -
              Number(eDaiReserves) +
              fee

        if (values[i][6]) {
          assert(
            'eDaiInForDaiOut (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              daiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            result[0]
          )
          assert(
            'eDaiInForDaiOut (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              daiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[1]',
            Math.abs(expected - Number(result[1])) <= Math.max(0.000001, expected / 100000.0)
          )
        } else {
          assert(
            '!eDaiInForDaiOut (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              daiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            !result[0]
          )
        }
      }
    })

    it('Test `daiInForEDaiOut` function', async () => {
      var values = [
        ['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        // ['0x0', '0x0', '0x0', '0x1', '0xFFFFFFFFFFFFFFFF', '0x10000000000000000', true, 0.0], // Testing too far from reality
        ['0x0', '0x0', '0x0', '0x1', '0x10000000000000000', '0x10000000000000000', false],
        [
          '0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
          '0x80000000000000000000000000000000',
          '0x80000000000000000000000000000000',
          '0x0',
          '0x0',
          '0x0',
          true,
        ],
        [
          '0x80000000000000000000000000000000',
          '0x80000000000000000000000000000000',
          '0x8000000000000000000000000000002D',
          '0x0',
          '0x0',
          '0x0',
          false,
        ],
        [
          // TODO: Consider fixing
          '0xFEDCBA9876543210',
          '0x123456789ABCDEF0',
          '0x123456789ABC',
          '0x1',
          '0x8000000000000000',
          '0xFEDCBA9876543210',
          true,
        ],
        // Use this to debug
        /* [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xf333333333333333',   // g = 950 / 1000 in 64.64
          true,                   // ?
        ], */
      ]

      for (var i = 0; i < values.length; i++) {
        // for (var j = 0; j < daiReserveValues.length; j++) {
        // var i = 0 // !
        var daiReservesValue = values[i][0]
        var eDaiReservesValue = values[i][1]
        var eDaiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /* console.log(
          '    daiInForEDaiOut (' +
            daiReservesValue +
            ', ' +
            eDaiReservesValue +
            ', ' +
            eDaiAmountValue +
            ', ' +
            timeTillMaturityValue +
            ', ' +
            kValue +
            ', ' +
            gValue +
            ')'
        ) */
        var daiReserves = toBigNumber(daiReservesValue)
        var eDaiReserves = toBigNumber(eDaiReservesValue)
        var eDaiAmount = toBigNumber(eDaiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.daiInForEDaiOut(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }

        /* console.log(
          '    daiInForEDaiOut (' +
            daiReserves.toString() +
            ', ' +
            eDaiReserves.toString() +
            ', ' +
            eDaiAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        ) */

        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
        var fee = Number(toBigNumber('1000000000000'))

        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(eDaiReserves), a) -
                  Math.pow(Number(eDaiReserves.sub(eDaiAmount)), a),
                1.0 / a
              ) -
              Number(daiReserves) +
              fee

        if (values[i][6]) {
          assert(
            'daiInForEDaiOut (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              eDaiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            result[0]
          )
          assert(
            'daiInForEDaiOut (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              eDaiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[1]',
            Math.abs(expected - Number(result[1])) <= Math.max(0.000001, expected / 100000.0)
          )
        } else {
          assert(
            '!daiInForEDaiOut (' +
              daiReservesValue +
              ', ' +
              eDaiReservesValue +
              ', ' +
              eDaiAmountValue +
              ', ' +
              timeTillMaturityValue +
              ', ' +
              kValue +
              ', ' +
              gValue +
              ')[0]',
            !result[0]
          )
        }
      }
    })

    it('Test rounding induced underflow', async () => {
      var daiReserves = toBigNumber('9295050963679385441209')
      var eDaiReserves = toBigNumber('10721945986215692199666')
      var daiAmount = toBigNumber('10000')
      var timeTillMaturity = toBigNumber('39971379')
      var k = toBigNumber('146235604338')
      var g = toBigNumber('19417625340746896437')

      await expectRevert(
        yieldMath.eDaiInForDaiOut(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g),
        'YieldMath: Rounding induced error'
      )
      await expectRevert(
        yieldMath.daiInForEDaiOut(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g),
        'YieldMath: Rounding induced error'
      )
    })
  })
})
