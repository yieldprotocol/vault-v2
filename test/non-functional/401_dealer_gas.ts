// @ts-ignore
import helper from 'ganache-time-traveler'
import { WETH, rate1 as rate, daiTokens1, wethTokens1 } from './../shared/utils'
import { YieldEnvironment, Contract } from './../shared/fixtures'

contract('Gas Usage', async (accounts) => {
  let [owner, user1, user2, user3] = accounts

  let snapshot: any
  let snapshotId: string

  let maturities: number[]
  let series: Contract[]

  let env: YieldEnvironment
  let controller: Contract
  let treasury: Contract
  let dai: Contract
  let unwind: Contract

  const m = 4

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturities = []
    for (let i = 1; i <= m; i++) {
      const maturity = (await web3.eth.getBlock(block)).timestamp + i * 1000
      maturities.push(maturity)
    }

    env = await YieldEnvironment.setup(maturities)
    controller = env.controller
    treasury = env.treasury
    dai = env.maker.dai
    unwind = env.unwind
    series = env.yDais
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  describe('post and borrow', () => {
    beforeEach(async () => {
      // Set the scenario

      for (let i = 0; i < maturities.length; i++) {
        await env.postWeth(user3, wethTokens1)
        await controller.borrow(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 })
      }
    })

    it('borrow a second time', async () => {
      for (let i = 0; i < maturities.length; i++) {
        await env.postWeth(user3, wethTokens1)
        await controller.borrow(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 })
      }
    })

    it('repayYDai', async () => {
      for (let i = 0; i < maturities.length; i++) {
        await series[i].approve(treasury.address, daiTokens1, { from: user3 })
        await controller.repayYDai(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 })
      }
    })

    it('repay all debt with repayYDai', async () => {
      for (let i = 0; i < maturities.length; i++) {
        await series[i].approve(controller.address, daiTokens1.mul(2), { from: user3 })
        await controller.repayYDai(WETH, maturities[i], user3, user3, daiTokens1.mul(2), { from: user3 })
      }
    })

    it('repayDai and withdraw', async () => {
      await helper.advanceTime(m * 1000)
      await helper.advanceBlock()

      for (let i = 0; i < maturities.length; i++) {
        await env.maker.getDai(user3, daiTokens1, rate)
        await dai.approve(treasury.address, daiTokens1, { from: user3 })
        await controller.repayDai(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 })
      }

      for (let i = 0; i < maturities.length; i++) {
        await controller.withdraw(WETH, user3, user3, wethTokens1, { from: user3 })
      }
    })

    describe('during dss unwind', () => {
      beforeEach(async () => {
        await env.shutdown(owner, user1, user2)
      })

      it('single series settle', async () => {
        await unwind.settle(WETH, user3, { from: user3 })
      })

      it('all series settle', async () => {
        await unwind.settle(WETH, user3, { from: user3 })
      })
    })
  })
})
