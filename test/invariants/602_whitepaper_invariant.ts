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
  const g2 = new BN('1000').mul(b).div(new BN('950')) // Sell yDai to the pool

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    test = await Test.new()
    yieldMath = await YieldMath.new()
  })

  it('Outputs the invariant for daiOutForYDaiIn', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxYDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minYDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const yDaiReserves = minYDaiReserves
    // const yDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    const daiReserves = new BN('1000000000000000000000')
    const yDaiReserves = new BN('1000000000000000000001')
    const yDaiIn = new BN('1000000000000000000')
    const timeTillMaturity = new BN('1')

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log(
      'Reserves value:      ' + (await test.whitepaperInvariant(daiReserves, yDaiReserves, timeTillMaturity)).toString()
    )
    const daiOut = await yieldMath.daiOutForYDaiIn64(daiReserves, yDaiReserves, yDaiIn, timeTillMaturity, k, g2)
    console.log('yDai in:             ' + yDaiIn.toString())
    console.log('Dai out:             ' + daiOut.toString())
    // console.log('yDai Reserves:       ' + yDaiReserves.add(yDaiIn).toString())
    // console.log('Dai Reserves:        ' + daiReserves.sub(daiOut).toString())
    // console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log(
      'Reserves value:      ' +
        (await test.whitepaperInvariant(daiReserves.sub(daiOut), yDaiReserves.add(yDaiIn), timeTillMaturity)).toString()
    )
    // console.log((await test.testLiquidityInvariant('66329041300990984000', '34400000000000000000', '10000000000000000000', '31556951')).toString());
  })

  it('Buys Dai and reverses the trade', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxYDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minYDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const yDaiReserves = minYDaiReserves
    // const yDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    const daiReserves = new BN('786100583545859324586665')
    const yDaiReserves = new BN('21446358147545110233910802')
    const daiOut = new BN('1000000001781921161')
    const timeTillMaturity = '94105225'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai out:             ' + daiOut.toString())

    console.log(
      'Reserves value:      ' + (await test.whitepaperInvariant(daiReserves, yDaiReserves, timeTillMaturity)).toString()
    )
    const yDaiAmount = await yieldMath.yDaiInForDaiOut64(daiReserves, yDaiReserves, daiOut, timeTillMaturity, k, g2)
    console.log('yDai intermediate:   ' + yDaiAmount.toString())
    console.log(
      'Reserves value:      ' +
        (
          await test.whitepaperInvariant(daiReserves.sub(daiOut), yDaiReserves.add(yDaiAmount), timeTillMaturity)
        ).toString()
    )
    const daiIn = await yieldMath.daiInForYDaiOut64(
      daiReserves.sub(daiOut),
      yDaiReserves.add(yDaiAmount),
      yDaiAmount,
      timeTillMaturity,
      k,
      g1
    )
    console.log('Dai in:              ' + daiIn.toString())
    console.log(
      'Reserves value:      ' +
        (await test.whitepaperInvariant(daiReserves.add(daiIn).sub(daiOut), yDaiReserves, timeTillMaturity)).toString()
    )
  })
})
