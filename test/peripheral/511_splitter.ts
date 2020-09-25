const Pool = artifacts.require('Pool')
const Splitter = artifacts.require('YieldProxy')

import { BigNumber } from 'ethers'
import { id } from 'ethers/lib/utils'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import {
  WETH,
  rate1,
  daiTokens1,
  wethTokens1,
  mulRay,
  divRay,
  bnify,
  almostEqual,
  precision,
  ZERO,
} from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'

import { assert, expect } from 'chai'

contract('YieldProxy - Splitter', async (accounts) => {
  let [owner, user] = accounts

  const eDaiTokens1 = daiTokens1
  let maturity1: number
  let env: YieldEnvironmentLite
  let dai: Contract
  let vat: Contract
  let controller: Contract
  let weth: Contract
  let eDai1: Contract
  let splitter1: Contract
  let pool1: Contract

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 30000000 // Far enough so that the extra weth to borrow is above dust

    env = await YieldEnvironmentLite.setup([maturity1])
    controller = env.controller
    vat = env.maker.vat
    dai = env.maker.dai
    weth = env.maker.weth

    eDai1 = env.eDais[0]

    // Setup Pool
    pool1 = await Pool.new(dai.address, eDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup Splitter
    splitter1 = await Splitter.new(controller.address, [pool1.address], { from: owner })

    // Allow owner to mint eDai the sneaky way, without recording a debt in controller
    await eDai1.orchestrate(owner, id('mint(address,uint256)'), { from: owner })

    // Initialize Pool1
    const daiReserves = bnify(daiTokens1).mul(5)
    await env.maker.getDai(owner, daiReserves, rate1)
    await dai.approve(pool1.address, daiReserves, { from: owner })
    await pool1.init(daiReserves, { from: owner })

    // Add eDai
    const additionalEDaiReserves = bnify(eDaiTokens1).mul(2)
    await eDai1.mint(owner, additionalEDaiReserves, { from: owner })
    await eDai1.approve(pool1.address, additionalEDaiReserves, { from: owner })
    await pool1.sellEDai(owner, owner, additionalEDaiReserves, { from: owner })
  })

  it('does not allow to move more debt than existing in maker', async () => {
    await expectRevert(
      splitter1.makerToYield(pool1.address, user, wethTokens1, bnify(daiTokens1).mul(10), { from: user }),
      'YieldProxy: Not enough debt in Maker'
    )
  })

  it('does not allow to move more weth than posted in maker', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)

    await expectRevert(
      splitter1.makerToYield(pool1.address, user, bnify(wethTokens1).mul(10), daiTokens1, { from: user }),
      'YieldProxy: Not enough collateral in Maker'
    )
  })

  it('moves maker vault to yield', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)
    const daiDebt = mulRay(bnify((await vat.urns(WETH, user)).art), rate1).toString()
    const wethCollateral = bnify((await vat.urns(WETH, user)).ink).toString()
    expect(daiDebt).to.be.bignumber.gt(ZERO)
    expect(wethCollateral).to.be.bignumber.gt(ZERO)

    // This lot can be avoided if the user is certain that he has enough Weth in Controller
    // The amount of eDai to be borrowed can be obtained from Pool through Splitter
    // As time passes, the amount of eDai required decreases, so this value will always be slightly higher than needed
    const eDaiNeeded = await splitter1.eDaiForDai(pool1.address, daiDebt)

    // Once we know how much eDai debt we will have, we can see how much weth we need to move
    const wethInController = bnify(await splitter1.wethForEDai(eDaiNeeded, { from: user }))

    // If we need any extra, we are posting it directly on Controller
    const extraWethNeeded = wethInController.sub(bnify(wethTokens1)) // It will always be zero or more
    await splitter1.post(user, { from: user, value: extraWethNeeded.toString() })

    // Add permissions for vault migration
    await controller.addDelegate(splitter1.address, { from: user }) // Allowing Splitter to create debt for use in Yield
    await vat.hope(splitter1.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO
    // Go!!!
    assert.equal((await controller.posted(WETH, user)).toString(), extraWethNeeded.toString())
    assert.equal((await controller.debtEDai(WETH, maturity1, user)).toString(), 0)

    await splitter1.makerToYield(pool1.address, user, wethTokens1, daiDebt, { from: user })

    assert.equal(await eDai1.balanceOf(splitter1.address), 0)
    assert.equal(await dai.balanceOf(splitter1.address), 0)
    assert.equal(await weth.balanceOf(splitter1.address), 0)
    assert.equal((await vat.urns(WETH, user)).ink, wethTokens1)
    assert.equal((await vat.urns(WETH, user)).art, 0)
    assert.equal((await controller.posted(WETH, user)).toString(), wethInController.toString())
    const eDaiDebt = await controller.debtEDai(WETH, maturity1, user)
    expect(eDaiDebt).to.be.bignumber.lt(eDaiNeeded)
    expect(eDaiDebt).to.be.bignumber.gt(eDaiNeeded.mul(new BN('9999')).div(new BN('10000')))
  })

  it('does not allow to move more debt than existing in env', async () => {
    await expectRevert(
      splitter1.yieldToMaker(pool1.address, user, wethTokens1, eDaiTokens1, { from: user }),
      'YieldProxy: Not enough debt in Yield'
    )
  })

  it('does not allow to move more weth than posted in env', async () => {
    await env.postWeth(user, wethTokens1)
    const toBorrow = (await env.unlockedOf(WETH, user)).toString()
    await controller.borrow(WETH, maturity1, user, user, toBorrow, { from: user })

    await expectRevert(
      splitter1.yieldToMaker(pool1.address, user, bnify(wethTokens1).mul(2), toBorrow, { from: user }),
      'YieldProxy: Not enough collateral in Yield'
    )
  })

  it('moves yield vault to maker', async () => {
    await env.postWeth(user, wethTokens1)
    const toBorrow = (await env.unlockedOf(WETH, user)).toString()
    await controller.borrow(WETH, maturity1, user, user, toBorrow, { from: user })

    // Add permissions for vault migration
    await controller.addDelegate(splitter1.address, { from: user }) // Allowing Splitter to create debt for use in Yield
    await vat.hope(splitter1.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO
    // Go!!!
    assert.equal((await controller.posted(WETH, user)).toString(), wethTokens1)
    assert.equal((await controller.debtEDai(WETH, maturity1, user)).toString(), toBorrow.toString())
    assert.equal((await vat.urns(WETH, user)).ink, 0)
    assert.equal((await vat.urns(WETH, user)).art, 0)
    assert.equal(await eDai1.balanceOf(splitter1.address), 0)

    // Will need this one for testing. As time passes, even for one block, the resulting dai debt will be higher than this value
    const makerDebtEstimate = new BN(await splitter1.daiForEDai(pool1.address, toBorrow))

    await splitter1.yieldToMaker(pool1.address, user, wethTokens1, toBorrow, { from: user })

    assert.equal(await eDai1.balanceOf(splitter1.address), 0)
    assert.equal(await dai.balanceOf(splitter1.address), 0)
    assert.equal(await weth.balanceOf(splitter1.address), 0)
    assert.equal((await controller.posted(WETH, user)).toString(), 0)
    assert.equal((await controller.debtEDai(WETH, maturity1, user)).toString(), 0)
    assert.equal((await vat.urns(WETH, user)).ink, wethTokens1)
    const makerDebt = mulRay((await vat.urns(WETH, user)).art.toString(), rate1).toString()
    expect(makerDebt).to.be.bignumber.gt(makerDebtEstimate)
    expect(makerDebt).to.be.bignumber.lt(makerDebtEstimate.mul(new BN('10001')).div(new BN('10000')))
  })
})
