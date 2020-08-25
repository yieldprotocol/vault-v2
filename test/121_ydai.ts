import { id } from 'ethers/lib/utils'
import { YieldEnvironmentLite, Contract } from './shared/fixtures'
const FlashMinterMock = artifacts.require('FlashMinterMock')
const FlashMintRedeemerMock = artifacts.require('FlashMintRedeemerMock')

import { WETH, chi1, rate1, daiTokens1, wethTokens1, toRay, mulRay, divRay, subBN } from './shared/utils'

// @ts-ignore
import helper from 'ganache-time-traveler'

// @ts-ignore
import { BN, expectEvent, expectRevert } from '@openzeppelin/test-helpers'

contract('yDai', async (accounts) => {
  let [owner, user1, user2] = accounts

  const rate2 = toRay(1.82)
  const chi2 = toRay(1.5)
  const chiDifferential = divRay(chi2, chi1)
  const daiTokens2 = mulRay(daiTokens1, chiDifferential)
  const wethTokens2 = mulRay(wethTokens1, chiDifferential)

  let maturity: number
  let snapshot: any
  let snapshotId: string

  let treasury: Contract
  let vat: Contract
  let weth: Contract
  let pot: Contract
  let dai: Contract
  let yDai1: Contract
  let flashMinter: Contract
  let env: YieldEnvironmentLite
  let flashMintRedeemer: Contract

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    const block = await web3.eth.getBlockNumber()
    maturity = (await web3.eth.getBlock(block)).timestamp + 1000

    env = await YieldEnvironmentLite.setup([maturity])
    treasury = env.treasury
    weth = env.maker.weth
    pot = env.maker.pot
    vat = env.maker.vat
    dai = env.maker.dai

    yDai1 = env.yDais[0]

    // Test setup
    // Setup Flash Minter
    flashMinter = await FlashMinterMock.new({ from: owner })

    flashMintRedeemer = await FlashMintRedeemerMock.new({ from: owner })

    // Deposit some weth to treasury the sneaky way so that redeem can pull some dai
    await treasury.orchestrate(owner, id('pushWeth(address,uint256)'), { from: owner })
    await weth.deposit({ from: owner, value: wethTokens2.mul(2).toString() })
    await weth.approve(treasury.address, wethTokens2.mul(2), { from: owner })
    await treasury.pushWeth(owner, wethTokens2.mul(2), { from: owner })

    // Mint some yDai1 the sneaky way, only difference is that the Controller doesn't record the user debt.
    await yDai1.orchestrate(owner, id('mint(address,uint256)'), { from: owner })
    await yDai1.mint(user1, daiTokens1, { from: owner })
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  it('should setup yDai1', async () => {
    assert.equal(await yDai1.chiGrowth(), toRay(1.0).toString(), 'chi not initialized')
    assert.equal(await yDai1.rateGrowth(), toRay(1.0).toString(), 'rate not initialized')
    assert.equal(await yDai1.maturity(), maturity.toString(), 'maturity not initialized')
  })

  it('should fail to set up yDai with an invalid maturity date', async () => {
    const block = await web3.eth.getBlockNumber()
    const timestamp = (await web3.eth.getBlock(block)).timestamp
    const earlyMaturity = timestamp - 1000
    const lateMaturity = timestamp + 126144000 + 15

    await expectRevert(env.newYDai(earlyMaturity, 'Name', 'Symbol'), 'YDai: Invalid maturity')

    await expectRevert(env.newYDai(lateMaturity, 'Name', 'Symbol'), 'YDai: Invalid maturity')
  })

  it('yDai1 is not mature before maturity', async () => {
    assert.equal(await yDai1.isMature(), false)
  })

  it("yDai1 can't be redeemed before maturity time", async () => {
    await expectRevert(yDai1.redeem(user1, user2, daiTokens1, { from: user1 }), 'YDai: yDai is not mature')
  })

  it('yDai1 cannot mature before maturity time', async () => {
    await expectRevert(yDai1.mature(), 'YDai: Too early to mature')
  })

  it('yDai1 can mature at maturity time', async () => {
    await helper.advanceTime(1000)
    await helper.advanceBlock()
    await yDai1.mature()
    assert.equal(await yDai1.isMature(), true)
  })

  it('yDai1 flash mints', async () => {
    const yDaiSupply = await yDai1.totalSupply()
    expectEvent(
      await flashMinter.flashMint(yDai1.address, daiTokens1, web3.utils.fromAscii('DATA'), { from: user1 }),
      'Parameters',
      {
        user: flashMinter.address,
        amount: daiTokens1.toString(),
        data: web3.utils.fromAscii('DATA'),
      }
    )

    assert.equal(await flashMinter.flashBalance(), daiTokens1.toString(), 'FlashMinter should have seen the tokens')
    assert.equal(await yDai1.totalSupply(), yDaiSupply.toString(), 'There should be no change in yDai supply')
  })

  it("yDai1 can't reach more than 2**112 supply on flash mint", async () => {
    const halfLimit = new BN('2').pow(new BN('111'))
    await yDai1.mint(user1, halfLimit, { from: owner })
    await expectRevert(
      flashMinter.flashMint(yDai1.address, halfLimit, web3.utils.fromAscii('DATA'), { from: user1 }),
      'YDai: Total supply limit exceeded'
    )
  })

  describe('once mature', () => {
    beforeEach(async () => {
      await helper.advanceTime(1000)
      await helper.advanceBlock()
      await yDai1.mature()
    })

    it("yDai1 can't mature more than once", async () => {
      await expectRevert(yDai1.mature(), 'YDai: Already mature')
    })

    it('yDai1 chi gets fixed at maturity time', async () => {
      await pot.setChi(chi2, { from: owner })

      assert.equal((await yDai1.chi0()).toString(), chi1.toString(), 'Chi at maturity should be ' + chi1)
    })

    it('yDai1 still flash mints', async () => {
      const yDaiSupply = await yDai1.totalSupply()
      expectEvent(
        await flashMinter.flashMint(yDai1.address, daiTokens1, web3.utils.fromAscii('DATA'), { from: user1 }),
        'Parameters',
        {
          user: flashMinter.address,
          amount: daiTokens1.toString(),
          data: web3.utils.fromAscii('DATA'),
        }
      )

      assert.equal(await flashMinter.flashBalance(), daiTokens1.toString(), 'FlashMinter should have seen the tokens')
      assert.equal(await yDai1.totalSupply(), yDaiSupply.toString(), 'There should be no change in yDai supply')
    })

    it('yDai1 cannot redeem during flash mint', async () => {
      const yDaiSupply = await yDai1.totalSupply()
      await expectRevert(
        flashMintRedeemer.flashMint(yDai1.address, daiTokens1, web3.utils.fromAscii('DATA'), { from: user1 }),
        'YDai: Locked'
      )
    })

    it('yDai1 rate gets fixed at maturity time', async () => {
      await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner })

      assert.equal((await yDai1.rate0()).toString(), rate1.toString(), 'Rate at maturity should be ' + rate1)
    })

    it('rateGrowth returns the rate differential between now and maturity', async () => {
      await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner })

      assert.equal(
        (await yDai1.rateGrowth()).toString(),
        divRay(rate2, rate1).toString(),
        'Rate differential should be ' + divRay(rate2, rate1)
      )
    })

    it('chiGrowth always <= rateGrowth', async () => {
      await pot.setChi(chi2, { from: owner })

      assert.equal(
        (await yDai1.chiGrowth()).toString(),
        (await yDai1.rateGrowth()).toString(),
        'Chi differential should be ' + (await yDai1.rateGrowth()) + ', instead is ' + (await yDai1.chiGrowth())
      )
    })

    it('chiGrowth returns the chi differential between now and maturity', async () => {
      await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner })
      await pot.setChi(chi2, { from: owner })

      assert.equal(
        (await yDai1.chiGrowth()).toString(),
        divRay(chi2, chi1).toString(),
        'Chi differential should be ' + divRay(chi2, chi1)
      )
    })

    it('redeem burns yDai1 to return dai, pulls dai from Treasury', async () => {
      assert.equal(await yDai1.balanceOf(user1), daiTokens1.toString(), 'User1 does not have yDai1')
      assert.equal(await dai.balanceOf(user2), 0, 'User2 has dai')

      await yDai1.approve(yDai1.address, daiTokens1, { from: user1 })
      await yDai1.redeem(user1, user2, daiTokens1, { from: user1 })

      assert.equal(await dai.balanceOf(user2), daiTokens1.toString(), 'User2 should have dai')
      assert.equal(await yDai1.balanceOf(user1), 0, 'User1 should not have yDai1')
    })

    describe('once chi increases', () => {
      beforeEach(async () => {
        await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner }) // Keeping above chi
        await pot.setChi(chi2, { from: owner })

        assert.equal(
          await yDai1.chiGrowth(),
          chiDifferential.toString(),
          'chi differential should be ' + chiDifferential + ', instead is ' + (await yDai1.chiGrowth())
        )
      })

      it('redeem with increased chi returns more dai', async () => {
        // Redeem `daiTokens1` yDai to obtain `daiTokens1` * `chiDifferential`

        assert.equal(await yDai1.balanceOf(user1), daiTokens1.toString(), 'User1 does not have yDai1')

        await yDai1.approve(yDai1.address, daiTokens1, { from: user1 })
        await yDai1.redeem(user1, user1, daiTokens1, { from: user1 })

        assert.equal(
          await dai.balanceOf(user1),
          daiTokens2.toString(),
          'User1 should have ' + daiTokens2 + ' dai, instead has ' + (await dai.balanceOf(user1))
        )
        assert.equal(
          await yDai1.balanceOf(user1),
          0,
          'User2 should have no yDai left, instead has ' + (await yDai1.balanceOf(user1))
        )
      })
    })
  })
})
