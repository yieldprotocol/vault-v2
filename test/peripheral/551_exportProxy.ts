const Pool = artifacts.require('Pool')
const ExportProxy = artifacts.require('ExportProxy')
const DSProxy = artifacts.require('DSProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

import { id } from 'ethers/lib/utils'
import { getSignatureDigest, userPrivateKey, sign } from '../shared/signatures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { WETH, rate1, daiTokens1, wethTokens1, mulRay, bnify, MAX, name, chainId } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'

import { assert, expect } from 'chai'

contract('ExportProxy', async (accounts) => {
  let [owner, user] = accounts

  const fyDaiTokens1 = daiTokens1
  let maturity1: number
  let env: YieldEnvironmentLite
  let dai: Contract
  let vat: Contract
  let controller: Contract
  let weth: Contract
  let fyDai1: Contract
  let exportProxy: Contract
  let pool1: Contract

  let proxyFactory: Contract
  let proxyRegistry: Contract
  let dsProxy: Contract

  beforeEach(async () => {
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 30000000 // Far enough so that the extra weth to borrow is above dust

    env = await YieldEnvironmentLite.setup([maturity1])
    controller = env.controller
    vat = env.maker.vat
    dai = env.maker.dai
    weth = env.maker.weth

    fyDai1 = env.fyDais[0]

    // Setup Pool
    pool1 = await Pool.new(dai.address, fyDai1.address, 'Name', 'Symbol', { from: owner })

    // Setup ExportProxy
    exportProxy = await ExportProxy.new(controller.address, [pool1.address], { from: owner })

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

    // Setup DSProxyFactory and DSProxyCache
    proxyFactory = await DSProxyFactory.new({ from: owner })

    // Setup DSProxyRegistry
    proxyRegistry = await DSProxyRegistry.new(proxyFactory.address, { from: owner })

    // Sets DSProxy for user
    await proxyRegistry.build({ from: user })
    dsProxy = await DSProxy.at(await proxyRegistry.proxies(user))
  })

  it('does not allow to execute the flash mint callback to users', async () => {
    const data = web3.eth.abi.encodeParameters(
      ['address', 'address', 'uint256', 'uint256'],
      [pool1.address, user, 1, 0]
    )
    await expectRevert(exportProxy.executeOnFlashMint(1, data, { from: user }), 'ExportProxy: Restricted callback')
  })

  it('does not allow to move more debt than existing in env', async () => {
    await expectRevert(
      exportProxy.exportPosition(pool1.address, wethTokens1, fyDaiTokens1, { from: user }),
      'ExportProxy: Not enough debt in Yield'
    )
  })

  it('does not allow to move more weth than posted in env', async () => {
    await env.postWeth(user, wethTokens1)
    const toBorrow = (await env.unlockedOf(WETH, user)).toString()
    await controller.borrow(WETH, maturity1, user, user, toBorrow, { from: user })

    await expectRevert(
      exportProxy.exportPosition(pool1.address, bnify(wethTokens1).mul(2), toBorrow, { from: user }),
      'ExportProxy: Not enough collateral in Yield'
    )
  })

  it('moves yield vault to maker', async () => {
    await env.postWeth(user, wethTokens1)
    const toBorrow = (await env.unlockedOf(WETH, user)).toString()
    await controller.borrow(WETH, maturity1, user, user, toBorrow, { from: user })

    // Add permissions for vault migration
    await controller.addDelegate(exportProxy.address, { from: user }) // Allowing ExportProxy to create debt for use in Yield
    await vat.hope(exportProxy.address, { from: user }) // Allowing ExportProxy to manipulate debt for user in MakerDAO
    // Go!!!
    assert.equal((await controller.posted(WETH, user)).toString(), wethTokens1)
    assert.equal((await controller.debtFYDai(WETH, maturity1, user)).toString(), toBorrow.toString())
    assert.equal((await vat.urns(WETH, user)).ink, 0)
    assert.equal((await vat.urns(WETH, user)).art, 0)
    assert.equal(await fyDai1.balanceOf(exportProxy.address), 0)

    // Will need this one for testing. As time passes, even for one block, the resulting dai debt will be higher than this value
    const makerDebtEstimate = new BN(await exportProxy.daiForFYDai(pool1.address, toBorrow))

    await exportProxy.exportPosition(pool1.address, wethTokens1, toBorrow, { from: user })

    assert.equal(await fyDai1.balanceOf(exportProxy.address), 0)
    assert.equal(await dai.balanceOf(exportProxy.address), 0)
    assert.equal(await weth.balanceOf(exportProxy.address), 0)
    assert.equal((await controller.posted(WETH, user)).toString(), 0)
    assert.equal((await controller.debtFYDai(WETH, maturity1, user)).toString(), 0)
    assert.equal((await vat.urns(WETH, user)).ink, wethTokens1)
    const makerDebt = mulRay((await vat.urns(WETH, user)).art.toString(), rate1).toString()
    expect(makerDebt).to.be.bignumber.gt(makerDebtEstimate)
    expect(makerDebt).to.be.bignumber.lt(makerDebtEstimate.mul(new BN('10001')).div(new BN('10000')))
  })

  it('moves yield vault to maker with a signature', async () => {
    await env.postWeth(user, wethTokens1)
    const toBorrow = (await env.unlockedOf(WETH, user)).toString()
    await controller.borrow(WETH, maturity1, user, user, toBorrow, { from: user })

    // Add permissions for vault migration

    // Authorize the proxy for the controller
    const controllerDigest = getSignatureDigest(
        name,
        controller.address,
        chainId,
        {
          user: user,
          delegate: exportProxy.address,
        },
        await controller.signatureCount(user),
        MAX
      )
      const controllerSig = sign(controllerDigest, userPrivateKey)
    await vat.hope(exportProxy.address, { from: user }) // Allowing ExportProxy to manipulate debt for user in MakerDAO

    await exportProxy.exportPositionWithSignature(pool1.address, wethTokens1, toBorrow, controllerSig, { from: user })
  })
})