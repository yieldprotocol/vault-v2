import { id } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
// @ts-ignore
import { expectRevert, expectEvent } from '@openzeppelin/test-helpers'
import { WETH, daiTokens1, wethTokens1 } from './shared/utils'
import { YieldEnvironmentLite, Contract } from './shared/fixtures'

contract('yDai - Delegation', async (accounts) => {
  let [owner, holder, other] = accounts

  let maturity1: number
  let maturity2: number

  let snapshot: any
  let snapshotId: string

  let treasury: Contract
  let vat: Contract
  let weth: Contract
  let dai: Contract
  let yDai1: Contract

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000
    maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000

    const env = await YieldEnvironmentLite.setup([maturity1, maturity2])
    treasury = env.treasury
    weth = env.maker.weth
    vat = env.maker.vat
    dai = env.maker.dai

    yDai1 = env.yDais[0]

    // Post collateral to MakerDAO through Treasury
    await treasury.orchestrate(owner, id('pushWeth(address,uint256)'), { from: owner })
    await weth.deposit({ from: owner, value: wethTokens1 })
    await weth.approve(treasury.address, wethTokens1, { from: owner })
    await treasury.pushWeth(owner, wethTokens1, { from: owner })
    assert.equal((await vat.urns(WETH, treasury.address)).ink, wethTokens1.toString())

    // Mint some yDai the sneaky way
    await yDai1.orchestrate(owner, id('mint(address,uint256)'), { from: owner })
    await yDai1.mint(holder, daiTokens1, { from: owner })

    // yDai matures
    await helper.advanceTime(1000)
    await helper.advanceBlock()
    await yDai1.mature()

    assert.equal(await yDai1.balanceOf(holder), daiTokens1.toString(), 'Holder does not have yDai')
    assert.equal(await treasury.savings(), 0, 'Treasury has no savings')
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  it('redeem is allowed for account holder', async () => {
    await yDai1.approve(yDai1.address, daiTokens1, { from: holder })
    await yDai1.redeem(holder, holder, daiTokens1, { from: holder })

    assert.equal(await treasury.debt(), daiTokens1.toString(), 'Treasury should have debt')
    assert.equal(await dai.balanceOf(holder), daiTokens1.toString(), 'Holder should have dai')
  })

  it('redeem is not allowed for non designated accounts', async () => {
    await yDai1.approve(yDai1.address, daiTokens1, { from: holder })
    await expectRevert(yDai1.redeem(holder, holder, daiTokens1, { from: other }), 'YDai: Only Holder Or Delegate')
  })

  it('redeem is allowed for delegates', async () => {
    await yDai1.approve(yDai1.address, daiTokens1, { from: holder })
    expectEvent(await yDai1.addDelegate(other, { from: holder }), 'Delegate', {
      user: holder,
      delegate: other,
      enabled: true,
    })
    await yDai1.redeem(holder, holder, daiTokens1, { from: other })

    assert.equal(await treasury.debt(), daiTokens1.toString(), 'Treasury should have debt')
    assert.equal(await dai.balanceOf(holder), daiTokens1.toString(), 'Holder should have dai')
  })

  describe('with delegates', async () => {
    beforeEach(async () => {
      await yDai1.addDelegate(other, { from: holder })
    })

    it('redeem is not allowed if delegation revoked', async () => {
      expectEvent(await yDai1.revokeDelegate(other, { from: holder }), 'Delegate', {
        user: holder,
        delegate: other,
        enabled: false,
      })

      await expectRevert(yDai1.redeem(holder, holder, daiTokens1, { from: other }), 'YDai: Only Holder Or Delegate')
    })

    it('cannot add delegate again or remove delegate twice', async () => {
      await expectRevert(yDai1.addDelegate(other, { from: holder }), 'Delegable: Already delegated')

      expectEvent(await yDai1.revokeDelegate(other, { from: holder }), 'Delegate', {
        user: holder,
        delegate: other,
        enabled: false,
      })

      await expectRevert(yDai1.revokeDelegate(other, { from: holder }), 'Delegable: Already undelegated')
    })
  })
})
