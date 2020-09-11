const Test = artifacts.require('TradeReversalInvariantWrapper')
const YieldMath = artifacts.require('YieldMathMock')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { bnify } from '../shared/utils'
import { Contract } from '../shared/fixtures'
// @ts-ignore

contract('YieldMath - Trade Reversal Invariant', async (accounts) => {
  let snapshot: any
  let snapshotId: string

  let test: Contract
  let yieldMath: Contract

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    test = await Test.new()
    yieldMath = await YieldMath.new()
  })

  it('Sells eDai and reverses the trade', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxEDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minEDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const eDaiReserves = minEDaiReserves
    // const eDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    let daiReserves = '1000000000000000000000'
    let eDaiReserves = '1000000000000000000001'
    let eDaiIn = '1000000000000000000'
    let timeTillMaturity = '0'

    console.log('eDai Reserves:       ' + eDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('eDai in:             ' + eDaiIn.toString())
    console.log(
      'eDai out:            ' +
        (await test.sellEDaiAndReverse(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity)).toString()
    )
  })

  it('Buys eDai and reverses the trade', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxEDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minEDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const eDaiReserves = minEDaiReserves
    // const eDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    const daiReserves = '349061773210894792196710'
    const eDaiReserves = '1001649248511020033788'
    const eDaiOut = '1000000000000000001'
    const timeTillMaturity = '49034'

    console.log('eDai Reserves:       ' + eDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('eDai out:             ' + eDaiOut.toString())
    console.log(
      'eDai in:            ' +
        (await test.buyEDaiAndReverse(daiReserves, eDaiReserves, eDaiOut, timeTillMaturity)).toString()
    )
  })

  it('Sells Dai and reverses the trade', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxEDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minEDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const eDaiReserves = minEDaiReserves
    // const eDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    let daiReserves = '1000000000000000000000'
    let eDaiReserves = '1000000000000000000001'
    let daiIn = '1000000000000000000'
    let timeTillMaturity = '0'

    console.log('eDai Reserves:       ' + eDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai in:              ' + daiIn.toString())
    console.log(
      'Dai out:             ' +
        (await test.sellDaiAndReverse(daiReserves, eDaiReserves, daiIn, timeTillMaturity)).toString()
    )

    daiReserves = '1133485'
    eDaiReserves = '83'
    daiIn = '1001108599807'
    timeTillMaturity = '770'
    console.log(
      'Pass:                ' +
        (await test.testSellDaiAndReverse(daiReserves, eDaiReserves, daiIn, timeTillMaturity)).toString()
    )
  })

  it('Buys Dai and reverses the trade', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxEDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minEDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const eDaiReserves = minEDaiReserves
    // const eDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    const daiReserves = '786100583545859324586665'
    const eDaiReserves = '21446358147545110233910802'
    const daiOut = '1000000001781921161'
    const timeTillMaturity = '94105225'

    console.log('eDai Reserves:       ' + eDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai out:             ' + daiOut.toString())
    console.log(
      'Dai in:            ' +
        (await test.bueDaiAndReverse(daiReserves, eDaiReserves, daiOut, timeTillMaturity)).toString()
    )
  })
})
