const Pool = artifacts.require('Pool')
const ImportProxy = artifacts.require('ImportProxy')
const ImportProxyMock = artifacts.require('ImportProxyMock')
const DSProxy = artifacts.require('DSProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

import { id } from 'ethers/lib/utils'
import { getSignatureDigest, userPrivateKey, sign } from '../shared/signatures'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import { WETH, rate1, daiTokens1, mulRay, bnify, MAX, name, chainId, ZERO } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'

import { assert, expect } from 'chai'

contract('ImportProxy', async (accounts) => {
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
  let importProxy: Contract
  let pool1: Contract

  let proxyFactory: Contract
  let proxyRegistry: Contract
  let dsProxy: Contract

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

    // Setup DSProxyFactory and DSProxyCache
    proxyFactory = await DSProxyFactory.new({ from: owner })

    // Setup DSProxyRegistry
    proxyRegistry = await DSProxyRegistry.new(proxyFactory.address, { from: owner })

    // Setup Splitter
    importProxy = await ImportProxy.new(controller.address, [pool1.address], proxyRegistry.address, { from: owner })

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

    // Sets DSProxy for user
    await proxyRegistry.build({ from: user })
    dsProxy = await DSProxy.at(await proxyRegistry.proxies(user))

    // Prime ImportProxy with some Dai to cover rounding losses
    await vat.move(owner, importProxy.address, '2040000000000000000000000000', { from: owner }) // 2.04 wei dai
  })

  it('allows setting hope/nope of ImportProxy to caller or its dsproxy only', async () => {
    assert.equal(await vat.can(importProxy.address, user), 0)
    await importProxy.hope(user, { from: user })
    assert.equal(await vat.can(importProxy.address, user), 1)
    await importProxy.nope(user, { from: user })
    assert.equal(await vat.can(importProxy.address, user), 0)
    await expectRevert(importProxy.hope(owner, { from: user }), 'Restricted to user or its dsproxy')
    await expectRevert(importProxy.nope(owner, { from: user }), 'Restricted to user or its dsproxy')

    const splitterMock = await ImportProxyMock.new(importProxy.address, { from: owner })
    let calldata = splitterMock.contract.methods.hope(user).encodeABI()
    await dsProxy.methods['execute(address,bytes)'](splitterMock.address, calldata, {
      from: user,
    })
    assert.equal(await vat.can(importProxy.address, dsProxy.address), 1)
    calldata = splitterMock.contract.methods.nope(user).encodeABI()
    await dsProxy.methods['execute(address,bytes)'](splitterMock.address, calldata, {
      from: user,
    })
    assert.equal(await vat.can(importProxy.address, dsProxy.address), 0)
  })

  it('does not allow to execute the flash mint callback to users', async () => {
    const data = web3.eth.abi.encodeParameters(
      ['address', 'address', 'uint256', 'uint256'],
      [pool1.address, user, 1, 0]
    )
    await expectRevert(
      importProxy.executeOnFlashMint(1, data, { from: user }),
      'Callback restricted to the fyDai matching the pool'
    )
  })

  it('does not allow to move more debt than existing in maker', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)
    await vat.hope(importProxy.address, { from: user })
    await importProxy.hope(user, { from: user })
    await vat.fork(
      WETH,
      user,
      importProxy.address,
      (await vat.urns(WETH, user)).ink,
      (await vat.urns(WETH, user)).art,
      { from: user }
    )
    const daiDebt = bnify((await vat.urns(WETH, importProxy.address)).art).toString()
    const wethCollateral = bnify((await vat.urns(WETH, importProxy.address)).ink).toString()

    await expectRevert(
      importProxy.importFromProxy(pool1.address, user, wethCollateral, bnify(daiDebt).mul(10), { from: user }),
      'ImportProxy: Not enough debt in Maker'
    )
  })

  it('does not allow to move more weth than posted in maker', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)
    await vat.hope(importProxy.address, { from: user })
    await importProxy.hope(user, { from: user })
    await vat.fork(
      WETH,
      user,
      importProxy.address,
      (await vat.urns(WETH, user)).ink,
      (await vat.urns(WETH, user)).art,
      { from: user }
    )
    const daiDebt = bnify((await vat.urns(WETH, importProxy.address)).art).toString()
    const wethCollateral = bnify((await vat.urns(WETH, importProxy.address)).ink).toString()

    await expectRevert(
      importProxy.importFromProxy(pool1.address, user, bnify(wethCollateral).mul(10), daiDebt, { from: user }),
      'ImportProxy: Not enough collateral in Maker'
    )
  })

  it('checks approvals and signatures to move maker vault to yield', async () => {
    let result = await importProxy.importPositionCheck({ from: user })
    assert.equal(result[0], false)
    assert.equal(result[1], false)

    await vat.hope(importProxy.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO
    result = await importProxy.importPositionCheck({ from: user })
    assert.equal(result[0], true)
    assert.equal(result[1], false)

    await controller.addDelegate(importProxy.address, { from: user }) // Allowing Splitter to create debt for use in Yield
    result = await importProxy.importPositionCheck({ from: user })
    assert.equal(result[0], true)
    assert.equal(result[1], true)
  })

  it('moves maker vault to yield', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)
    const daiDebt = bnify((await vat.urns(WETH, user)).art).toString()
    const wethCollateral = bnify((await vat.urns(WETH, user)).ink).toString()
    expect(daiDebt).to.be.bignumber.gt(ZERO)
    expect(wethCollateral).to.be.bignumber.gt(ZERO)

    // daiDebt: Normalized dai debt in MakerDAO
    // daiMaker: Actual dai borrowed
    // fyDaiDebt: fyDai to be bought in the pool to create the yield position
    // daiYield: Value of created Yield position, in dai

    const daiMaker = mulRay(daiDebt, rate1).toString()
    const fyDaiDebt = (await importProxy.fyDaiForDai(pool1.address, daiMaker)).toString()
    const daiYield = (await controller.inDai(WETH, maturity1, fyDaiDebt)).toString()
    // console.log(daiDebt)
    // console.log(daiMaker)
    // console.log(fyDaiDebt)
    // console.log(daiYield)

    // Add permissions for vault migration
    await controller.addDelegate(importProxy.address, { from: user }) // Allowing Splitter to create debt for use in Yield
    await vat.hope(importProxy.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO

    // Fork the vault off to importProxy
    await importProxy.hope(user, { from: user })
    await vat.fork(
      WETH,
      user,
      importProxy.address,
      (await vat.urns(WETH, user)).ink,
      (await vat.urns(WETH, user)).art,
      { from: user }
    )

    await importProxy.importFromProxy(pool1.address, user, wethCollateral, daiDebt, { from: user })

    assert.equal(await fyDai1.balanceOf(importProxy.address), 0)
    assert.equal(await dai.balanceOf(importProxy.address), 0)
    assert.equal(await weth.balanceOf(importProxy.address), 0)
    assert.equal((await vat.urns(WETH, user)).ink, 0)
    assert.equal((await vat.urns(WETH, user)).art, 0)
    assert.equal((await controller.posted(WETH, user)).toString(), wethCollateral.toString())
    const obtainedFYDaiDebt = (await controller.debtFYDai(WETH, maturity1, user)).toString()
    expect(obtainedFYDaiDebt).to.be.bignumber.gt(new BN(fyDaiDebt).mul(new BN('9999')).div(new BN('10000')))
    expect(obtainedFYDaiDebt).to.be.bignumber.lt(new BN(fyDaiDebt).mul(new BN('10000')).div(new BN('9999')))
  })

  it('forks and moves maker vault to yield', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)
    const daiDebt = bnify((await vat.urns(WETH, user)).art).toString()
    const wethCollateral = bnify((await vat.urns(WETH, user)).ink).toString()
    expect(daiDebt).to.be.bignumber.gt(ZERO)
    expect(wethCollateral).to.be.bignumber.gt(ZERO)

    // daiDebt: Normalized dai debt in MakerDAO
    // daiMaker: Actual dai borrowed
    // fyDaiDebt: fyDai to be bought in the pool to create the yield position
    // daiYield: Value of created Yield position, in dai

    const daiMaker = mulRay(daiDebt, rate1).toString()
    const fyDaiDebt = (await importProxy.fyDaiForDai(pool1.address, daiMaker)).toString()
    const daiYield = (await controller.inDai(WETH, maturity1, fyDaiDebt)).toString()
    // console.log(daiDebt)
    // console.log(daiMaker)
    // console.log(fyDaiDebt)
    // console.log(daiYield)

    // Add permissions for vault migration
    await controller.addDelegate(importProxy.address, { from: user }) // Allowing Splitter to create debt for use in Yield
    await vat.hope(dsProxy.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO

    // Go!!!
    const calldata = importProxy.contract.methods
      .importPosition(pool1.address, user, wethCollateral, daiDebt)
      .encodeABI()
    await dsProxy.methods['execute(address,bytes)'](importProxy.address, calldata, {
      from: user,
    })

    assert.equal(await fyDai1.balanceOf(importProxy.address), 0)
    assert.equal(await dai.balanceOf(importProxy.address), 0)
    assert.equal(await weth.balanceOf(importProxy.address), 0)
    assert.equal((await vat.urns(WETH, user)).ink, 0)
    assert.equal((await vat.urns(WETH, user)).art, 0)
    assert.equal((await controller.posted(WETH, user)).toString(), wethCollateral.toString())
    const obtainedFYDaiDebt = (await controller.debtFYDai(WETH, maturity1, user)).toString()
    expect(obtainedFYDaiDebt).to.be.bignumber.gt(new BN(fyDaiDebt).mul(new BN('9999')).div(new BN('10000')))
    expect(obtainedFYDaiDebt).to.be.bignumber.lt(new BN(fyDaiDebt).mul(new BN('10000')).div(new BN('9999')))
  })

  it('forks and moves maker vault to yield with signature', async () => {
    await env.maker.getDai(user, daiTokens1, rate1)
    const daiDebt = bnify((await vat.urns(WETH, user)).art).toString()
    const wethCollateral = bnify((await vat.urns(WETH, user)).ink).toString()
    expect(daiDebt).to.be.bignumber.gt(ZERO)
    expect(wethCollateral).to.be.bignumber.gt(ZERO)

    // Authorize the proxy for the controller
    const controllerDigest = getSignatureDigest(
      name,
      controller.address,
      chainId,
      {
        user: user,
        delegate: importProxy.address,
      },
      await controller.signatureCount(user),
      MAX
    )
    const controllerSig = sign(controllerDigest, userPrivateKey)

    // Add permissions for vault migration
    await vat.hope(dsProxy.address, { from: user }) // Allowing Splitter to manipulate debt for user in MakerDAO

    // Go!!!
    const calldata = importProxy.contract.methods
      .importPositionWithSignature(pool1.address, user, wethCollateral, daiDebt, controllerSig)
      .encodeABI()
    await dsProxy.methods['execute(address,bytes)'](importProxy.address, calldata, {
      from: user,
    })
  })

  it('fork and split is restricted to vault owners or their proxies', async () => {
    await expectRevert(
      importProxy.importPosition(pool1.address, user, 1, 1, { from: owner }),
      'Restricted to user or its dsproxy'
    )
  })

  it('importFromProxy is restricted to vault owners or their proxies', async () => {
    await expectRevert(
      importProxy.importFromProxy(pool1.address, user, 1, 1, { from: owner }),
      'Restricted to user or its dsproxy'
    )
  })
})
