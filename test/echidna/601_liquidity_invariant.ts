const Test = artifacts.require('YieldMathEchidna')
const YieldMath = artifacts.require('YieldMathMock')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { bnify } from '../shared/utils'
import { Contract } from '../shared/fixtures'
// @ts-ignore

contract('YieldMath', async (accounts) => {
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

  it('log_2 monotonically grows', async () => {
    console.log('    ' + (await yieldMath.log_2_128('4000916067400943041987521580724335131')).toString())
    console.log('    ' + (await yieldMath.log_2_128('4000916067400943041987521580724335132')).toString())
  })

  it('log_2 precission losses round down', async () => {
    console.log('    ' + (await yieldMath.log_2_64('4000916067400943041987521580724335131')).toString())
    console.log('    ' + (await yieldMath.log_2_128('4000916067400943041987521580724335132')).toString())
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

    const daiReserves =   '998999999999999999998'
    const yDaiReserves = '1001000000000000000001'
    const yDaiIn =          '1000000000000000000'
    const timeTillMaturity = '43199'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('yDai in:             ' + yDaiIn.toString())
    console.log('Reserves value:      ' + (await test.initialReservesValue(daiReserves, yDaiReserves, timeTillMaturity)).toString());
    const daiOut = bnify(await yieldMath.daiOutForYDaiIn128(daiReserves, yDaiReserves, yDaiIn, timeTillMaturity, k, g));
    console.log('Dai out:             ' + daiOut.toString())
    console.log('Reserves value:      ' + 
      bnify(
        await test.initialReservesValue(
          bnify(daiReserves).sub(daiOut).toString(),
          bnify(yDaiReserves).add(yDaiIn).toString(),
          bnify(timeTillMaturity).sub(1).toString(),
        )
      ).toString()
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

    const daiReserves =   '1000000000000000000000'
    const yDaiReserves = '1000000000000000000001'
    const yDaiIn =          '1000000000000000000'
    const timeTillMaturity = '43200'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('yDai in:             ' + yDaiIn.toString())
    console.log('yDai out:            ' + (await test.sellYDaiAndReverse(daiReserves, yDaiReserves, yDaiIn, timeTillMaturity)).toString());
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

    const daiReserves =   '349061773210894792196710'
    const yDaiReserves = '1001649248511020033788'
    const yDaiOut =          '1000000000000000001'
    const timeTillMaturity = '49034'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('yDai out:             ' + yDaiOut.toString())
    console.log('yDai in:            ' + (await test.buyYDaiAndReverse(daiReserves, yDaiReserves, yDaiOut, timeTillMaturity)).toString());
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

    const daiReserves =   '349061773210894792196710'
    const yDaiReserves = '1001649248511020033788'
    const daiIn =          '1000000000000000001'
    const timeTillMaturity = '49034'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai in:             ' + daiIn.toString())
    console.log('Dai out:            ' + (await test.sellDaiAndReverse(daiReserves, yDaiReserves, daiIn, timeTillMaturity)).toString());
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

    const daiReserves =   '925173878424482809107308121'
    const yDaiReserves = '623579633693919687679844805'
    const daiOut =          '1001078616452680644'
    const timeTillMaturity = '33'

    console.log('yDai Reserves:       ' + yDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai out:             ' + daiOut.toString())
    console.log('Dai in:            ' + (await test.buyDaiAndReverse(daiReserves, yDaiReserves, daiOut, timeTillMaturity)).toString());
  })
})
