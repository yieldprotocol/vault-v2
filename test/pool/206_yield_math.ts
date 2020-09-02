const YieldMath = artifacts.require('YieldMathDAIWrapper')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { Contract } from '../shared/fixtures'
// @ts-ignore
import { BN } from '@openzeppelin/test-helpers'

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

contract('YieldMath', async (accounts) => {
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
        console.log('    log_2 (' + xValue + ')')
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
        console.log('    pow_2 (' + xValue + ')')
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
          console.log('    pow (' + xValue + ', ' + yValue + ', ' + zValue + ')')
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

  describe.only('Test trading functions', async () => {
    var timeTillMaturityValues = ['0x0', '0xf', '0xff', '0xfff', '0xffff', '0xfffff', '0xffffff', '0x784ce00']
    var daiReserveValues = ['0x52b7d2dcc80cd2e4000000', '0xa56fa5b99019a5c8000000', '0x14adf4b7320334b90000000', '0x295be96e640669720000000']
    var yDaiReserveValues = ['0x52b7d2dcc80cd2e4000001', '0xa56fa5b99019a5c8000001', '0x14adf4b7320334b90000001', '0x295be96e640669720000001']

    it('Test `yDaiOutForDaiIn` function', async () => {
      var values = [
        /*['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
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
        ],*/
        [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xffbe76c8b4395810',   // g = 999 / 1000 in 64.64
          true,                   // ?
        ],
      ]
  
      // for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < daiReserveValues.length; j++) {
        var i = 0 // !
        var daiReservesValue = daiReserveValues[j]
        var yDAIReservesValue = yDaiReserveValues[j]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /*
        console.log(
          '    yDaiOutForDaiIn (' +
            daiReservesValue +
            ', ' +
            yDAIReservesValue +
            ', ' +
            daiAmountValue +
            ', ' +
            timeTillMaturityValue +
            ', ' +
            kValue +
            ', ' +
            gValue +
            ')'
        )
        */
        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }
  
        console.log(
          '    yDaiOutForDaiIn (' +
            daiReserves.toString() +
            ', ' +
            yDAIReserves.toString() +
            ', ' +
            daiAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        )
  
        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
  
        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Number(yDAIReserves) -
              Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(yDAIReserves), a) -
                  Math.pow(Number(daiReserves.add(daiAmount)), a),
                1.0 / a
              )
  
        if (values[i][6]) {
          assert(
            'yDaiOutForDaiIn (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
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
            'yDaiOutForDaiIn (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
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
            '!yDaiOutForDaiIn (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
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
  
    it('Test `daiOutForYDaiIn` function', async () => {
      var values = [
        /*['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
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
        ],*/
        [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xffbe76c8b4395810',   // g = 999 / 1000 in 64.64
          true,                   // ?
        ],
      ]
  
      // for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < daiReserveValues.length; j++) {
        var i = 0 // !
        var daiReservesValue = daiReserveValues[j]
        var yDAIReservesValue = yDaiReserveValues[j]
        var yDAIAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /* console.log(
          '    daiOutForYDaiIn (' +
            daiReservesValue +
            ', ' +
            yDAIReservesValue +
            ', ' +
            yDAIAmountValue +
            ', ' +
            timeTillMaturityValue +
            ', ' +
            kValue +
            ', ' +
            gValue +
            ')'
        ) */
        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var yDAIAmount = toBigNumber(yDAIAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.daiOutForYDaiIn(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }
    
        console.log(
          '    daiOutForYDaiIn (' +
            daiReserves.toString() +
            ', ' +
            yDAIReserves.toString() +
            ', ' +
            yDAIAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        )

        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
  
        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Number(daiReserves) -
              Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(yDAIReserves), a) -
                  Math.pow(Number(yDAIReserves.add(yDAIAmount)), a),
                1.0 / a
              )
  
        if (values[i][6]) {
          assert(
            'daiOutForYDaiIn (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
              ', ' +
              yDAIAmountValue +
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
            'daiOutForYDaiIn (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
              ', ' +
              yDAIAmountValue +
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
            '!daiOutForYDaiIn (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
              ', ' +
              yDAIAmountValue +
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
  
    it('Test `yDaiInForDaiOut` function', async () => {
      var values = [
        /*['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        ['0x0', '0x0', '0x0', '0x1', '0xFFFFFFFFFFFFFFFF', '0x10000000000000000', true, 0.0],
        ['0x0', '0x0', '0x0', '0x1', '0x10000000000000000', '0x10000000000000000', false],
        ['0x80000000000000000000000000000000', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
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
        ],*/
        [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xffbe76c8b4395810',   // g = 999 / 1000 in 64.64
          true,                   // ?
        ],
      ]
  
      // for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < daiReserveValues.length; j++) {
        var i = 0 // !
        var daiReservesValue = daiReserveValues[j]
        var yDAIReservesValue = yDaiReserveValues[j]
        var daiAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /* console.log(
          '    yDaiInForDaiOut (' +
            daiReservesValue +
            ', ' +
            yDAIReservesValue +
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
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var daiAmount = toBigNumber(daiAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }

        console.log(
          '    yDaiInForDaiOut (' +
            daiReserves.toString() +
            ', ' +
            yDAIReserves.toString() +
            ', ' +
            daiAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        )

        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
  
        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(yDAIReserves), a) -
                  Math.pow(Number(daiReserves.sub(daiAmount)), a),
                1.0 / a
              ) - Number(yDAIReserves)
  
        if (values[i][6]) {
          assert(
            'yDaiInForDaiOut (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
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
            'yDaiInForDaiOut (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
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
            '!yDaiInForDaiOut (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
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
  
    it('Test `daiInForYDaiOut` function', async () => {
      var values = [
        /*['0x0', '0x0', '0x0', '0x0', '0x0', '0x0', true],
        ['0x0', '0x0', '0x1', '0x0', '0x0', '0x0', false],
        ['0x0', '0x0', '0x0', '0x1', '0xFFFFFFFFFFFFFFFF', '0x10000000000000000', true, 0.0],
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
          '0xFEDCBA9876543210',
          '0x123456789ABCDEF0',
          '0x123456789ABC',
          '0x1',
          '0x8000000000000000',
          '0xFEDCBA9876543210',
          true,
        ],*/
        [
          '0x3635c9adc5dea00000', // d0 = 10**21
          '0x3635c9adc5dea00000', // d1 = 10**21
          '0xde0b6b3a8640000',    // tradeSize ~= 1e18
          '0x4c4b40',             // timeTillMaturity
          '0x220c523d73',         // k = 1 / 126144000 in 64.64
          '0xffbe76c8b4395810',   // g = 999 / 1000 in 64.64
          true,                   // ?
        ],
      ]
  
      // for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < daiReserveValues.length; j++) {
        var i = 0 // !
        var daiReservesValue = daiReserveValues[j]
        var yDAIReservesValue = yDaiReserveValues[j]
        var yDAIAmountValue = values[i][2]
        var timeTillMaturityValue = values[i][3]
        var kValue = values[i][4]
        var gValue = values[i][5]
        /* console.log(
          '    daiInForYDaiOut (' +
            daiReservesValue +
            ', ' +
            yDAIReservesValue +
            ', ' +
            yDAIAmountValue +
            ', ' +
            timeTillMaturityValue +
            ', ' +
            kValue +
            ', ' +
            gValue +
            ')'
        ) */
        var daiReserves = toBigNumber(daiReservesValue)
        var yDAIReserves = toBigNumber(yDAIReservesValue)
        var yDAIAmount = toBigNumber(yDAIAmountValue)
        var timeTillMaturity = toBigNumber(timeTillMaturityValue)
        var k = toBigNumber(kValue)
        var g = toBigNumber(gValue)
        var result
        try {
          result = await yieldMath.daiInForYDaiOut(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g)
        } catch (e) {
          result = [false, undefined]
        }

        console.log(
          '    daiInForYDaiOut (' +
            daiReserves.toString() +
            ', ' +
            yDAIReserves.toString() +
            ', ' +
            yDAIAmount.toString() +
            ', ' +
            timeTillMaturity.toString() +
            ') = ' +
            result[1].toString()
        )
  
        var nk = Number(k) / Number(toBigNumber('0x10000000000000000'))
        var ng = Number(g) / Number(toBigNumber('0x10000000000000000'))
  
        var a = 1.0 - ng * nk * Number(timeTillMaturity)
        var expected: any =
          values[i][7] !== undefined
            ? values[i][7]
            : Math.pow(
                Math.pow(Number(daiReserves), a) +
                  Math.pow(Number(yDAIReserves), a) -
                  Math.pow(Number(yDAIReserves.sub(yDAIAmount)), a),
                1.0 / a
              ) - Number(daiReserves)
  
        if (values[i][6]) {
          assert(
            'daiInForYDaiOut (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
              ', ' +
              yDAIAmountValue +
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
            'daiInForYDaiOut (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
              ', ' +
              yDAIAmountValue +
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
            '!daiInForYDaiOut (' +
              daiReservesValue +
              ', ' +
              yDAIReservesValue +
              ', ' +
              yDAIAmountValue +
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
  });
})
