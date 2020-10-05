const YieldMathMock = artifacts.require('YieldMathMock')
import { Contract } from '../shared/fixtures'

contract('Pool', async () => {
  let yieldMath: Contract

  const fyDaiReserves = '200000000000000000000000000'
  const daiReserves = '100000000000000000000000000'

  const oneYear = 31556952
  const k = '146235604338'
  const g = '18428297329635842000'

  let timeTillMaturity: number

  const results = new Set()
  results.add(['trade', 'daiReserves', 'fyDaiReserves', 'tokensIn', 'tokensOut'])

  beforeEach(async () => {
    // Setup YieldMathMock
    yieldMath = await YieldMathMock.new()
  })

  describe('using values from the library', () => {
    beforeEach(async () => {
      timeTillMaturity = oneYear
    })

    it('sells dai', async () => {
      for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
        let fyDaiOut = await yieldMath.fyDaiOutForDaiIn128(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai128', daiReserves, fyDaiReserves, trade, fyDaiOut])

        fyDaiOut = await yieldMath.fyDaiOutForDaiIn64(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai64', daiReserves, fyDaiReserves, trade, fyDaiOut])

        fyDaiOut = await yieldMath.fyDaiOutForDaiIn(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai48', daiReserves, fyDaiReserves, trade, fyDaiOut])
      }
    })

    it('buys dai', async () => {
      for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
        let fyDaiIn = await yieldMath.fyDaiInForDaiOut128(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['buyDai128', daiReserves, fyDaiReserves, fyDaiIn, trade])

        fyDaiIn = await yieldMath.fyDaiInForDaiOut64(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['buyDai64', daiReserves, fyDaiReserves, fyDaiIn, trade])

        fyDaiIn = await yieldMath.fyDaiInForDaiOut(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['buyDai48', daiReserves, fyDaiReserves, fyDaiIn, trade])
      }
    })

    it('sells fyDai', async () => {
      for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
        let daiOut = await yieldMath.daiOutForFYDaiIn128(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai128', daiReserves, fyDaiReserves, trade, daiOut])

        daiOut = await yieldMath.daiOutForFYDaiIn64(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai64', daiReserves, fyDaiReserves, trade, daiOut])

        daiOut = await yieldMath.daiOutForFYDaiIn(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai48', daiReserves, fyDaiReserves, trade, daiOut])
      }
    })

    it('buys fyDai', async () => {
      for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
        let daiIn = await yieldMath.daiInForFYDaiOut128(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['buyDai128', daiReserves, fyDaiReserves, daiIn, trade])

        daiIn = await yieldMath.daiInForFYDaiOut64(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['buyDai64', daiReserves, fyDaiReserves, daiIn, trade])

        daiIn = await yieldMath.daiInForFYDaiOut(daiReserves, fyDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['buyDai48', daiReserves, fyDaiReserves, daiIn, trade])
      }
    })

    it('prints results', async () => {
      let line: string[]
      // @ts-ignore
      for (line of results.values()) {
        console.log(
          '| ' +
            line[0].padEnd(12, ' ') +
            '· ' +
            line[1].toString().padEnd(30, ' ') +
            '· ' +
            line[2].toString().padEnd(30, ' ') +
            '· ' +
            line[3].toString().padEnd(30, ' ') +
            '· ' +
            line[4].toString().padEnd(30, ' ') +
            '|'
        )
      }
    })
  })
})
