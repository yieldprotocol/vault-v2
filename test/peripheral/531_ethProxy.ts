// Peripheral
const EthProxy = artifacts.require('EthProxy')

// @ts-ignore
import helper from 'ganache-time-traveler'
// @ts-ignore
import { balance } from '@openzeppelin/test-helpers'
import { WETH, daiTokens1, wethTokens1 } from '../shared/utils'
import { Contract, YieldEnvironmentLite } from '../shared/fixtures'

contract('Controller - EthProxy', async (accounts) => {
  let [owner, user1, user2] = accounts

  let snapshot: any
  let snapshotId: string

  let vat: Contract
  let controller: Contract
  let treasury: Contract
  let ethProxy: Contract
  let weth: Contract

  let maturity1: number
  let maturity2: number

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    const env = await YieldEnvironmentLite.setup()
    controller = env.controller
    treasury = env.treasury
    vat = env.maker.vat
    weth = env.maker.weth

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000
    maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000
    await env.newYDai(maturity1, 'Name', 'Symbol')
    await env.newYDai(maturity2, 'Name', 'Symbol')

    // Setup EthProxy
    ethProxy = await EthProxy.new(weth.address, treasury.address, controller.address, { from: owner })
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  it('allows user to post eth', async () => {
    assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury has weth in MakerDAO')
    assert.equal(await controller.powerOf(WETH, user2), 0, 'User2 has borrowing power')

    const previousBalance = await balance.current(user1)
    await ethProxy.post(user2, wethTokens1, { from: user1, value: wethTokens1 })

    expect(await balance.current(user1)).to.be.bignumber.lt(previousBalance)
    assert.equal(
      (await vat.urns(WETH, treasury.address)).ink,
      wethTokens1.toString(),
      'Treasury should have weth in MakerDAO'
    )
    assert.equal(
      await controller.powerOf(WETH, user2),
      daiTokens1.toString(),
      'User2 should have ' + daiTokens1 + ' borrowing power, instead has ' + (await controller.powerOf(WETH, user2))
    )
  })

  describe('with posted eth', () => {
    beforeEach(async () => {
      await ethProxy.post(user1, wethTokens1, { from: user1, value: wethTokens1 })

      assert.equal(
        (await vat.urns(WETH, treasury.address)).ink,
        wethTokens1.toString(),
        'Treasury does not have weth in MakerDAO'
      )
      assert.equal(await controller.powerOf(WETH, user1), daiTokens1.toString(), 'User1 does not have borrowing power')
      assert.equal(await weth.balanceOf(user2), 0, 'User2 has collateral in hand')
    })

    it('allows user to withdraw weth', async () => {
      await controller.addDelegate(ethProxy.address, { from: user1 })
      const previousBalance = await balance.current(user2)
      await ethProxy.withdraw(user2, wethTokens1, { from: user1 })

      expect(await balance.current(user2)).to.be.bignumber.gt(previousBalance)
      assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury should not not have weth in MakerDAO')
      assert.equal(await controller.powerOf(WETH, user1), 0, 'User1 should not have borrowing power')
    })
  })
})
