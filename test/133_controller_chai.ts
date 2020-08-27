import { id } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import {
  WETH,
  CHAI,
  precision,
  rate1,
  chi1,
  daiTokens1,
  chaiTokens1,
  toRay,
  addBN,
  subBN,
  mulRay,
  divRay,
  almostEqual,
  bnify,
} from './shared/utils'
import { YieldEnvironmentLite, MakerEnvironment, Contract } from './shared/fixtures'
import { BigNumber } from 'ethers'

contract('Controller - Chai', async (accounts) => {
  let [owner, user1, user2] = accounts

  let snapshot: any
  let snapshotId: string
  let maker: MakerEnvironment
  let env: YieldEnvironmentLite

  let dai: Contract
  let vat: Contract
  let pot: Contract
  let controller: Contract
  let yDai1: Contract
  let chai: Contract
  let treasury: Contract

  let maturity1: number
  let maturity2: number

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000
    maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000

    env = await YieldEnvironmentLite.setup([maturity1, maturity2])
    maker = env.maker
    controller = env.controller
    treasury = env.treasury
    pot = env.maker.pot
    vat = env.maker.vat
    dai = env.maker.dai
    chai = env.maker.chai

    yDai1 = env.yDais[0]

    // Tests setup
    await maker.getChai(user1, chaiTokens1, chi1, rate1)
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  it('allows user to post chai', async () => {
    assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury has chai')
    assert.equal(await controller.powerOf(CHAI, user1), 0, 'User1 has borrowing power')

    await chai.approve(treasury.address, chaiTokens1, { from: user1 })
    await controller.post(CHAI, user1, user1, chaiTokens1, { from: user1 })

    assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury should have chai')
    almostEqual(await controller.powerOf(CHAI, user1), daiTokens1.toString())
  })

  describe('with posted chai', () => {
    beforeEach(async () => {
      // Add some funds to the system to allow for rounding losses
      await maker.getChai(owner, 1000, chi1, rate1)
      await chai.approve(treasury.address, 1000, { from: owner })
      await controller.post(CHAI, owner, owner, 1000, { from: owner })

      await chai.approve(treasury.address, chaiTokens1, { from: user1 })
      await controller.post(CHAI, user1, user1, chaiTokens1, { from: user1 })
    })

    it('allows user to withdraw chai', async () => {
      almostEqual(await controller.powerOf(CHAI, user1), daiTokens1.toString(), precision)
      assert.equal(await chai.balanceOf(user1), 0, 'User1 has collateral in hand')

      await controller.withdraw(CHAI, user1, user1, chaiTokens1, { from: user1 })

      assert.equal(await chai.balanceOf(user1), chaiTokens1.toString(), 'User1 should have collateral in hand')
      assert.equal(await controller.powerOf(CHAI, user1), 0, 'User1 should not have borrowing power')
    })

    it('allows to borrow yDai', async () => {
      almostEqual(await controller.powerOf(CHAI, user1), daiTokens1.toString(), precision)
      almostEqual(await yDai1.balanceOf(user1), 0, precision)
      almostEqual(await controller.debtDai(CHAI, maturity1, user1), 0, precision)

      const toBorrow = await controller.powerOf(CHAI, user1)
      await controller.borrow(CHAI, maturity1, user1, user1, toBorrow, { from: user1 })

      almostEqual(await yDai1.balanceOf(user1), daiTokens1.toString(), precision)
      almostEqual(await controller.debtDai(CHAI, maturity1, user1), daiTokens1.toString(), precision)
    })

    it("doesn't allow to borrow yDai beyond borrowing power", async () => {
      almostEqual(await controller.powerOf(CHAI, user1), daiTokens1.toString(), precision)
      almostEqual(await controller.debtDai(CHAI, maturity1, user1), 0, precision)

      const toBorrow = bnify(await env.unlockedOf(CHAI, user1)).add(precision)
      await expectRevert(
        controller.borrow(CHAI, maturity1, user1, user1, toBorrow, { from: user1 }),
        'Controller: Too much debt'
      )
    })

    describe('with borrowed yDai', () => {
      beforeEach(async () => {
        const toBorrow = await env.unlockedOf(CHAI, user1)
        await controller.borrow(CHAI, maturity1, user1, user1, toBorrow, { from: user1 })
      })

      it("doesn't allow to withdraw and become undercollateralized", async () => {
        almostEqual(await controller.powerOf(CHAI, user1), daiTokens1.toString(), precision)
        almostEqual(await controller.debtDai(CHAI, maturity1, user1), daiTokens1.toString(), precision)

        await expectRevert(
          controller.borrow(CHAI, maturity1, user1, user1, chaiTokens1, { from: user1 }),
          'Controller: Too much debt'
        )
      })

      it('allows to repay yDai', async () => {
        almostEqual(await yDai1.balanceOf(user1), daiTokens1.toString(), precision)
        const debt = await controller.debtYDai(CHAI, maturity1, user1)

        await yDai1.approve(treasury.address, debt, { from: user1 })
        await controller.repayYDai(CHAI, maturity1, user1, user1, debt, { from: user1 })

        almostEqual(await yDai1.balanceOf(user1), 0, precision)
        assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 should not have debt')
      })

      it('allows to repay yDai with dai', async () => {
        // Borrow dai
        await maker.getDai(user1, daiTokens1, rate1)

        assert.equal(await dai.balanceOf(user1), daiTokens1.toString(), 'User1 does not have dai')
        const debt = await controller.debtDai(CHAI, maturity1, user1)
        almostEqual(debt.toString(), daiTokens1.toString(), precision)

        await dai.approve(treasury.address, debt, { from: user1 })
        await controller.repayDai(CHAI, maturity1, user1, user1, debt, { from: user1 })

        almostEqual(await dai.balanceOf(user1), 0, precision)
        assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 should not have debt')
      })

      it('when dai is provided in excess for repayment, only the necessary amount is taken', async () => {
        // Mint some yDai the sneaky way
        await yDai1.orchestrate(owner, id('mint(address,uint256)'), { from: owner })
        await yDai1.mint(user1, 1, { from: owner }) // 1 extra yDai wei
        const yDaiTokens = addBN(daiTokens1, 1) // daiTokens1 + 1 wei

        almostEqual(await yDai1.balanceOf(user1), yDaiTokens.toString(), precision)
        almostEqual(await controller.debtDai(CHAI, maturity1, user1), daiTokens1.toString(), precision)

        await yDai1.approve(treasury.address, yDaiTokens, { from: user1 })
        await controller.repayYDai(CHAI, maturity1, user1, user1, yDaiTokens, { from: user1 })

        assert.equal(await yDai1.balanceOf(user1), 1, 'User1 should have yDai left')
        assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 should not have debt')
      })

      let chiDifferential: BigNumber
      let rate2: BigNumber
      let chi2: BigNumber

      describe('after maturity, with a chi increase', () => {
        beforeEach(async () => {
          almostEqual(await yDai1.balanceOf(user1), daiTokens1.toString(), precision)
          almostEqual(await controller.debtDai(CHAI, maturity1, user1), daiTokens1.toString(), precision)
          // yDai matures
          await helper.advanceTime(1000)
          await helper.advanceBlock()
          await yDai1.mature()

          // Increase chi
          const chiIncrease = toRay(0.25)
          chiDifferential = divRay(addBN(chi1, chiIncrease), chi1)
          chi2 = chi1.add(chiIncrease)
          await pot.setChi(chi2, { from: owner })

          // Increase rate by a factor larger than chi
          rate2 = mulRay(rate1, chiDifferential).add(toRay(0.1))
          await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner }) // Keeping above chi
        })

        it('as chi increases after maturity, so does the debt in when measured in dai', async () => {
          almostEqual(await controller.debtDai(CHAI, maturity1, user1), mulRay(daiTokens1, chiDifferential), precision)
        })

        it("as chi increases after maturity, the debt doesn't in when measured in yDai", async () => {
          almostEqual(await controller.debtYDai(CHAI, maturity1, user1), daiTokens1.toString(), precision)
        })

        it('borrowing after maturity is still allowed', async () => {
          const yDaiDebt: BigNumber = daiTokens1
          const increasedChai: BigNumber = mulRay(chaiTokens1, chiDifferential)
          await maker.getChai(user2, addBN(increasedChai, 1), chi2, rate2)
          await chai.approve(treasury.address, increasedChai, { from: user2 })
          await controller.post(CHAI, user2, user2, increasedChai, { from: user2 })
          await controller.borrow(CHAI, maturity1, user2, user2, yDaiDebt, { from: user2 })

          assert.equal(
            await controller.debtYDai(CHAI, maturity1, user2),
            yDaiDebt.toString(),
            'User2 should have ' +
              yDaiDebt +
              ' yDai debt, instead has ' +
              (await controller.debtYDai(CHAI, maturity1, user2))
          )
          almostEqual(await controller.debtDai(CHAI, maturity1, user2), mulRay(daiTokens1, chiDifferential))
        })
      })
    })
  })
})
