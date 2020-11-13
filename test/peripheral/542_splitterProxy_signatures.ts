const Pool = artifacts.require('Pool')
const Splitter = artifacts.require('SplitterProxy')

import { getSignatureDigest, userPrivateKey, sign } from '../shared/signatures'
import { id } from 'ethers/lib/utils'
// @ts-ignore
import { WETH, rate1, daiTokens1, wethTokens1, mulRay, bnify, MAX, chainId, name } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'


contract('SplitterProxy', async (accounts) => {
  let [owner, user] = accounts

  const fyDaiTokens1 = daiTokens1
  let maturity1: number
  let env: YieldEnvironmentLite
  let dai: Contract
  let vat: Contract
  let treasury: Contract
  let controller: Contract
  let weth: Contract
  let fyDai1: Contract
  let proxy: Contract
  let pool1: Contract

  let controllerSig: any, poolSig: any

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 30000000 // Far enough so that the extra weth to borrow is above dust

    env = await YieldEnvironmentLite.setup([maturity1])
    treasury = env.treasury
    controller = env.controller
    vat = env.maker.vat
    dai = env.maker.dai
    weth = env.maker.weth

    fyDai1 = env.fyDais[0]

    // Setup Pool
    pool1 = await Pool.new(dai.address, fyDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup Splitter
    proxy = await Splitter.new(controller.address, { from: owner })

    // Allow owner to mint fyDai the sneaky way, without recording a debt in controller
    await fyDai1.orchestrate(owner, id('mint(address,uint256)'), { from: owner })

    // Initialize Pool1
    const daiReserves = bnify(daiTokens1).mul(5)
    await env.maker.getDai(owner, daiReserves, rate1)
    await dai.approve(pool1.address, daiReserves, { from: owner })
    await pool1.mint(owner, owner, daiReserves, { from: owner })

    // Add fyDai
    const additionalFYDaiReserves = bnify(fyDaiTokens1).mul(2)
    await fyDai1.mint(owner, additionalFYDaiReserves, { from: owner })
    await fyDai1.approve(pool1.address, additionalFYDaiReserves, { from: owner })
    await pool1.sellFYDai(owner, owner, additionalFYDaiReserves, { from: owner })

    // Authorize the proxy for the controller
    const controllerDigest = getSignatureDigest(
      name,
      controller.address,
      chainId,
      {
        user: user,
        delegate: proxy.address,
      },
      await controller.signatureCount(user),
      MAX
    )
    controllerSig = sign(controllerDigest, userPrivateKey)
  })

  it('moves maker vault to yield', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)
    const daiDebt = mulRay(bnify((await vat.urns(WETH, user)).art), rate1).toString()

    // This lot can be avoided if the user is certain that he has enough Weth in Controller
    // The amount of fyDai to be borrowed can be obtained from Pool through Splitter
    // As time passes, the amount of fyDai required decreases, so this value will always be slightly higher than needed
    const fyDaiNeeded = await proxy.fyDaiForDai(pool1.address, daiDebt)

    // Once we know how much fyDai debt we will have, we can see how much weth we need to move
    const wethInController = bnify(await proxy.wethForFYDai(fyDaiNeeded, { from: user }))

    // If we need any extra, we are posting it directly on Controller
    const extraWethNeeded = wethInController.sub(bnify(wethTokens1)) // It will always be zero or more
    await weth.deposit({ from: user, value: extraWethNeeded.toString() })
    await weth.approve(treasury.address, MAX, { from: user })
    await controller.post(WETH, user, user, extraWethNeeded, { from: user })

    // Add permissions for vault migration
    await vat.hope(proxy.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO
    await proxy.makerToYieldWithSignature(pool1.address, wethTokens1, daiDebt, controllerSig, { from: user })
  })

  it('moves yield vault to maker', async () => {
    await env.postWeth(user, wethTokens1)
    const toBorrow = (await env.unlockedOf(WETH, user)).toString()
    await controller.borrow(WETH, maturity1, user, user, toBorrow, { from: user })

    // Add permissions for vault migration
    await vat.hope(proxy.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO

    await proxy.yieldToMakerWithSignature(pool1.address, wethTokens1, toBorrow, controllerSig, { from: user })
  })
})
