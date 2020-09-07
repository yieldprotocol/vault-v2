const Test = artifacts.require('ReservesValueInvariantWrapper')
const YieldMath = artifacts.require('YieldMathMock')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { Contract } from '../shared/fixtures'
// @ts-ignore
import { BN } from '@openzeppelin/test-helpers'

contract('YieldMath - Trade Reversal Invariant', async (accounts) => {
  let snapshot: any
  let snapshotId: string

  let test: Contract
  let yieldMath: Contract

  const b = new BN('18446744073709551615')
  const k = b.div(new BN('126144000'))

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    test = await Test.new()
    yieldMath = await YieldMath.new()
  })

  it('Outputs the invariant for two consecutive seconds', async () => {
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
    const yDaiReserves = new BN('1000000000000858822563')
    const yDaiIn = new BN('1146442275045955069')
    const timeTillMaturity = new BN('23711349')
    const timeStep = new BN('1')

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log(
      'Reserves value:      ' + (await test.reservesValue(daiReserves, yDaiReserves, timeTillMaturity)).toString()
    )
    const daiOut = await yieldMath.daiOutForYDaiIn(daiReserves, yDaiReserves, yDaiIn, timeTillMaturity, k, g)
    console.log('yDai in:             ' + yDaiIn.toString())
    console.log('Dai out:             ' + daiOut.toString())
    console.log('yDai Reserves:       ' + yDaiReserves.add(yDaiIn).toString())
    console.log('Dai Reserves:        ' + daiReserves.sub(daiOut).toString())
    console.log('Time until maturity: ' + timeTillMaturity.sub(timeStep).toString())
    console.log(
      'Reserves value:      ' +
        (
          await test.reservesValue(daiReserves.sub(daiOut), yDaiReserves.add(yDaiIn), timeTillMaturity.sub(timeStep))
        ).toString()
    )
    // console.log((await test.testLiquidityInvariant('66329041300990984000', '34400000000000000000', '10000000000000000000', '31556951')).toString());
  })
})
