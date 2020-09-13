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

  it('Outputs the invariant for daiOutForEDaiIn', async () => {
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

    const daiReserves = new BN('1000000000000000000000')
    const eDaiReserves = new BN('1000000000000000000001')
    const eDaiIn = new BN('1000000000000000000')
    const timeTillMaturity = new BN('1')

    console.log('eDai Reserves:       ' + eDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log(
      'Reserves value:      ' + (await test.whitepaperInvariant(daiReserves, eDaiReserves, timeTillMaturity)).toString()
    )
    const daiOut = await yieldMath.daiOutForEDaiIn64(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity, k, g2)
    console.log('eDai in:             ' + eDaiIn.toString())
    console.log('Dai out:             ' + daiOut.toString())
    // console.log('eDai Reserves:       ' + eDaiReserves.add(eDaiIn).toString())
    // console.log('Dai Reserves:        ' + daiReserves.sub(daiOut).toString())
    // console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log(
      'Reserves value:      ' +
        (await test.whitepaperInvariant(daiReserves.sub(daiOut), eDaiReserves.add(eDaiIn), timeTillMaturity)).toString()
    )
    // console.log((await test.testLiquidityInvariant('66329041300990984000', '34400000000000000000', '10000000000000000000', '31556951')).toString());
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

    const daiReserves = new BN('786100583545859324586665')
    const eDaiReserves = new BN('21446358147545110233910802')
    const daiOut = new BN('1000000001781921161')
    const timeTillMaturity = '94105225'

    console.log('eDai Reserves:       ' + eDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai out:             ' + daiOut.toString())

    console.log(
      'Reserves value:      ' + (await test.whitepaperInvariant(daiReserves, eDaiReserves, timeTillMaturity)).toString()
    )
    const eDaiAmount = await yieldMath.eDaiInForDaiOut64(daiReserves, eDaiReserves, daiOut, timeTillMaturity, k, g2)
    console.log('eDai intermediate:   ' + eDaiAmount.toString())
    console.log(
      'Reserves value:      ' +
        (
          await test.whitepaperInvariant(daiReserves.sub(daiOut), eDaiReserves.add(eDaiAmount), timeTillMaturity)
        ).toString()
    )
    const daiIn = await yieldMath.daiInForEDaiOut64(
      daiReserves.sub(daiOut),
      eDaiReserves.add(eDaiAmount),
      eDaiAmount,
      timeTillMaturity,
      k,
      g1
    )
    console.log('Dai in:              ' + daiIn.toString())
    console.log(
      'Reserves value:      ' +
        (await test.whitepaperInvariant(daiReserves.add(daiIn).sub(daiOut), eDaiReserves, timeTillMaturity)).toString()
    )
  })
})
