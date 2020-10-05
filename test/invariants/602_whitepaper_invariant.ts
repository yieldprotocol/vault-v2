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
  const g2 = new BN('1000').mul(b).div(new BN('950')) // Sell fyDai to the pool

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup YieldMathDAIWrapper
    test = await Test.new()
    yieldMath = await YieldMath.new()
  })

  it('Outputs the invariant for daiOutForFYDaiIn', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxFYDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minFYDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const fyDaiReserves = minFYDaiReserves
    // const fyDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    const daiReserves = new BN('1000000000000000000000')
    const fyDaiReserves = new BN('1000000000000000000001')
    const fyDaiIn = new BN('1000000000000000000')
    const timeTillMaturity = new BN('1')

    console.log('fyDai Reserves:       ' + fyDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log(
      'Reserves value:      ' +
        (await test.whitepaperInvariant(daiReserves, fyDaiReserves, timeTillMaturity)).toString()
    )
    const daiOut = await yieldMath.daiOutForFYDaiIn64(daiReserves, fyDaiReserves, fyDaiIn, timeTillMaturity, k, g2)
    console.log('fyDai in:             ' + fyDaiIn.toString())
    console.log('Dai out:             ' + daiOut.toString())
    // console.log('fyDai Reserves:       ' + fyDaiReserves.add(fyDaiIn).toString())
    // console.log('Dai Reserves:        ' + daiReserves.sub(daiOut).toString())
    // console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log(
      'Reserves value:      ' +
        (
          await test.whitepaperInvariant(daiReserves.sub(daiOut), fyDaiReserves.add(fyDaiIn), timeTillMaturity)
        ).toString()
    )
    // console.log((await test.testLiquidityInvariant('66329041300990984000', '34400000000000000000', '10000000000000000000', '31556951')).toString());
  })

  it('Buys Dai and reverses the trade', async () => {
    // maxDaiReserves = 10**27; // $1B
    // maxFYDaiReserves = 10**27; // $1B
    // maxTrade = 10**26; // $100M
    // maxTimeTillMaturity = 31556952;

    // const minDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minFYDaiReserves = '1000000000000000000000' // 10**21; // $1000
    // const minTrade = '1000000000000000000' // 10**18; // $1
    // const minTimeTillMaturity = 1;

    // const daiReserves = minDaiReserves
    // const fyDaiReserves = minFYDaiReserves
    // const fyDaiIn = minTrade
    // const timeTillMaturity = minTimeTillMaturity

    const daiReserves = new BN('786100583545859324586665')
    const fyDaiReserves = new BN('21446358147545110233910802')
    const daiOut = new BN('1000000001781921161')
    const timeTillMaturity = '94105225'

    console.log('fyDai Reserves:       ' + fyDaiReserves.toString())
    console.log('Dai Reserves:        ' + daiReserves.toString())
    console.log('Time until maturity: ' + timeTillMaturity.toString())
    console.log('Dai out:             ' + daiOut.toString())

    console.log(
      'Reserves value:      ' +
        (await test.whitepaperInvariant(daiReserves, fyDaiReserves, timeTillMaturity)).toString()
    )
    const fyDaiAmount = await yieldMath.fyDaiInForDaiOut64(daiReserves, fyDaiReserves, daiOut, timeTillMaturity, k, g2)
    console.log('fyDai intermediate:   ' + fyDaiAmount.toString())
    console.log(
      'Reserves value:      ' +
        (
          await test.whitepaperInvariant(daiReserves.sub(daiOut), fyDaiReserves.add(fyDaiAmount), timeTillMaturity)
        ).toString()
    )
    const daiIn = await yieldMath.daiInForFYDaiOut64(
      daiReserves.sub(daiOut),
      fyDaiReserves.add(fyDaiAmount),
      fyDaiAmount,
      timeTillMaturity,
      k,
      g1
    )
    console.log('Dai in:              ' + daiIn.toString())
    console.log(
      'Reserves value:      ' +
        (await test.whitepaperInvariant(daiReserves.add(daiIn).sub(daiOut), fyDaiReserves, timeTillMaturity)).toString()
    )
  })
})
