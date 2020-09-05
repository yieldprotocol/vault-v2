const Test = artifacts.require('ReservesValueInvariantWrapper')
const YieldMath = artifacts.require('YieldMathMock')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { bnify } from '../shared/utils'
import { Contract } from '../shared/fixtures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'

contract('YieldMath - Trade Reversal Invariant', async (accounts) => {
  let snapshot: any
  let snapshotId: string

  let test: Contract
  let yieldMath: Contract

  const b = bnify('18446744073709551615')
  const k = bnify('126144000').div(b)
  const g = bnify('999').mul(b).div(1000)

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    test = await Test.new()
    yieldMath = await YieldMath.new()
  })

  it.only('Outputs the invariant for two consecutive seconds', async () => {
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

    // FAILS: testLiquidityDaiOutForYDaiIn(0,858822562,146442275045955069,2138027133)
    const daiReserves = new BN('1000000000000000000000')
    const yDaiReserves = new BN('1000000000000858822563')
    const yDaiIn = new BN('1146442275045955069')
    const timeTillMaturity = new BN('23711349')
    const timeStep = new BN('1')

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('yDai in:             ' + yDaiIn.toString())
    console.log(
      'Reserves value:      ' + (await test.reservesValue(daiReserves, yDaiReserves, timeTillMaturity)).toString()
    )
    const daiOut = await yieldMath.daiOutForYDaiIn(daiReserves, yDaiReserves, yDaiIn, timeTillMaturity, k, g)
    console.log('Dai out:             ' + daiOut.toString())
    console.log('Reserves value:      ' +
        (await test.reservesValue(daiReserves.sub(daiOut), yDaiReserves.add(yDaiIn), timeTillMaturity.sub(timeStep))).toString()
    )
    // console.log((await test.testLiquidityInvariant('66329041300990984000', '34400000000000000000', '10000000000000000000', '31556951')).toString());
  })

  it('Sells yDai and reverses the trade', async () => {
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

    const daiReserves = '996046632372301188284076'
    const yDaiReserves = '1000000000000000000001'
    const yDaiIn = '1000000000432404785'
    const timeTillMaturity = '1994870'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('yDai in:             ' + yDaiIn.toString())
    console.log(
      'yDai out:            ' +
        (await test.sellYDaiAndReverse(daiReserves, yDaiReserves, yDaiIn, timeTillMaturity)).toString()
    )
  })

  it('Buys yDai and reverses the trade', async () => {
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

    const daiReserves = '349061773210894792196710'
    const yDaiReserves = '1001649248511020033788'
    const yDaiOut = '1000000000000000001'
    const timeTillMaturity = '49034'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('yDai out:             ' + yDaiOut.toString())
    console.log(
      'yDai in:            ' +
        (await test.buyYDaiAndReverse(daiReserves, yDaiReserves, yDaiOut, timeTillMaturity)).toString()
    )
  })

  it('Sells Dai and reverses the trade', async () => {
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

    let daiReserves = '1000000000000001133485'
    let yDaiReserves = '1000000000000000000084'
    let daiIn = '1000001001108599807'
    let timeTillMaturity = '770'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai in:              ' + daiIn.toString())
    console.log(
      'Dai out:             ' +
        (await test.sellDaiAndReverse(daiReserves, yDaiReserves, daiIn, timeTillMaturity)).toString()
    )

    daiReserves = '1133485'
    yDaiReserves = '83'
    daiIn = '1001108599807'
    timeTillMaturity = '770'
    console.log(
      'Pass:                ' +
        (await test.testSellDaiAndReverse(daiReserves, yDaiReserves, daiIn, timeTillMaturity)).toString()
    )
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

    const daiReserves = '925173878424482809107308121'
    const yDaiReserves = '623579633693919687679844805'
    const daiOut = '1001078616452680644'
    const timeTillMaturity = '33'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai out:             ' + daiOut.toString())
    console.log(
      'Dai in:            ' +
        (await test.buyDaiAndReverse(daiReserves, yDaiReserves, daiOut, timeTillMaturity)).toString()
    )
  })
})
