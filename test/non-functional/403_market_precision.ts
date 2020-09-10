const YieldMathMock = artifacts.require('YieldMathMock')
import { Contract } from '../shared/fixtures'

contract('Pool', async () => {
  let yieldMath: Contract

  const eDaiReserves = '200000000000000000000000000'
  const daiReserves = '100000000000000000000000000'

  const oneYear = 31556952
  const k = '146235604338'
  const g = '18428297329635842000'

  let timeTillMaturity: number

  const results = new Set()
  results.add(['trade', 'daiReserves', 'eDaiReserves', 'tokensIn', 'tokensOut'])

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
        let eDaiOut = await yieldMath.eDaiOutForDaiIn128(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai128', daiReserves, eDaiReserves, trade, eDaiOut])

        eDaiOut = await yieldMath.eDaiOutForDaiIn64(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai64', daiReserves, eDaiReserves, trade, eDaiOut])

        eDaiOut = await yieldMath.eDaiOutForDaiIn(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai48', daiReserves, eDaiReserves, trade, eDaiOut])
      }
    })

    it('buys dai', async () => {
      for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
        let eDaiIn = await yieldMath.eDaiInForDaiOut128(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['bueDai128', daiReserves, eDaiReserves, eDaiIn, trade])

        eDaiIn = await yieldMath.eDaiInForDaiOut64(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['bueDai64', daiReserves, eDaiReserves, eDaiIn, trade])

        eDaiIn = await yieldMath.eDaiInForDaiOut(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['bueDai48', daiReserves, eDaiReserves, eDaiIn, trade])
      }
    })

    it('sells eDai', async () => {
      for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
        let daiOut = await yieldMath.daiOutForEDaiIn128(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai128', daiReserves, eDaiReserves, trade, daiOut])

        daiOut = await yieldMath.daiOutForEDaiIn64(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai64', daiReserves, eDaiReserves, trade, daiOut])

        daiOut = await yieldMath.daiOutForEDaiIn(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['sellDai48', daiReserves, eDaiReserves, trade, daiOut])
      }
    })

    it('buys eDai', async () => {
      for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
        let daiIn = await yieldMath.daiInForEDaiOut128(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['bueDai128', daiReserves, eDaiReserves, daiIn, trade])

        daiIn = await yieldMath.daiInForEDaiOut64(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['bueDai64', daiReserves, eDaiReserves, daiIn, trade])

        daiIn = await yieldMath.daiInForEDaiOut(daiReserves, eDaiReserves, trade, timeTillMaturity, k, g)

        results.add(['bueDai48', daiReserves, eDaiReserves, daiIn, trade])
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
