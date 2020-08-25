import { id } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { WETH, CHAI, rate1, chi1, daiTokens1, chaiTokens1, toRay, addBN, subBN, mulRay, divRay } from './shared/utils'
import { YieldEnvironmentLite, MakerEnvironment, Contract } from './shared/fixtures'
import { BigNumber } from 'ethers'

contract('Controller - Chai', async (accounts) => {
  let [owner, user1, user2] = accounts

  let snapshot: any
  let snapshotId: string
  let maker: MakerEnvironment

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

    const env = await YieldEnvironmentLite.setup([maturity1, maturity2])
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
    assert.equal(
      await controller.powerOf(CHAI, user1),
      daiTokens1.toString(),
      'User1 should have ' + daiTokens1 + ' borrowing power, instead has ' + (await controller.powerOf(CHAI, user1))
    )
  })

  describe('with posted chai', () => {
    beforeEach(async () => {
      await chai.approve(treasury.address, chaiTokens1, { from: user1 })
      await controller.post(CHAI, user1, user1, chaiTokens1, { from: user1 })
    })

    it('allows user to withdraw chai', async () => {
      assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury does not have chai')
      assert.equal(await controller.powerOf(CHAI, user1), daiTokens1.toString(), 'User1 does not have borrowing power')
      assert.equal(await chai.balanceOf(user1), 0, 'User1 has collateral in hand')

      await controller.withdraw(CHAI, user1, user1, chaiTokens1, { from: user1 })

      assert.equal(await chai.balanceOf(user1), chaiTokens1.toString(), 'User1 should have collateral in hand')
      assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury should not have chai')
      assert.equal(await controller.powerOf(CHAI, user1), 0, 'User1 should not have borrowing power')
    })

    it('allows to borrow yDai', async () => {
      assert.equal(await controller.powerOf(CHAI, user1), daiTokens1.toString(), 'User1 does not have borrowing power')
      assert.equal(await yDai1.balanceOf(user1), 0, 'User1 has yDai')
      assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 has debt')

      await controller.borrow(CHAI, maturity1, user1, user1, daiTokens1, { from: user1 })

      assert.equal(await yDai1.balanceOf(user1), daiTokens1.toString(), 'User1 should have yDai')
      assert.equal(await controller.debtDai(CHAI, maturity1, user1), daiTokens1.toString(), 'User1 should have debt')
    })

    it("doesn't allow to borrow yDai beyond borrowing power", async () => {
      assert.equal(await controller.powerOf(CHAI, user1), daiTokens1.toString(), 'User1 does not have borrowing power')
      assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 has debt')

      await expectRevert(
        controller.borrow(CHAI, maturity1, user1, user1, addBN(daiTokens1, 1), { from: user1 }),
        'Controller: Too much debt'
      )
    })

    describe('with borrowed yDai', () => {
      beforeEach(async () => {
        await controller.borrow(CHAI, maturity1, user1, user1, daiTokens1, { from: user1 })
      })

      it("doesn't allow to withdraw and become undercollateralized", async () => {
        assert.equal(
          await controller.powerOf(CHAI, user1),
          daiTokens1.toString(),
          'User1 does not have borrowing power'
        )
        assert.equal(
          await controller.debtDai(CHAI, maturity1, user1),
          daiTokens1.toString(),
          'User1 does not have debt'
        )

        await expectRevert(
          controller.borrow(CHAI, maturity1, user1, user1, chaiTokens1, { from: user1 }),
          'Controller: Too much debt'
        )
      })

      it('allows to repay yDai', async () => {
        assert.equal(await yDai1.balanceOf(user1), daiTokens1.toString(), 'User1 does not have yDai')
        assert.equal(
          await controller.debtDai(CHAI, maturity1, user1),
          daiTokens1.toString(),
          'User1 does not have debt'
        )

        await yDai1.approve(treasury.address, daiTokens1, { from: user1 })
        await controller.repayYDai(CHAI, maturity1, user1, user1, daiTokens1, { from: user1 })

        assert.equal(await yDai1.balanceOf(user1), 0, 'User1 should not have yDai')
        assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 should not have debt')
      })

      it('allows to repay yDai with dai', async () => {
        // Borrow dai
        await maker.getDai(user1, daiTokens1, rate1)

        assert.equal(await dai.balanceOf(user1), daiTokens1.toString(), 'User1 does not have dai')
        assert.equal(
          await controller.debtDai(CHAI, maturity1, user1),
          daiTokens1.toString(),
          'User1 does not have debt'
        )

        await dai.approve(treasury.address, daiTokens1, { from: user1 })
        await controller.repayDai(CHAI, maturity1, user1, user1, daiTokens1, { from: user1 })

        assert.equal(await dai.balanceOf(user1), 0, 'User1 should not have yDai')
        assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 should not have debt')
      })

      it('when dai is provided in excess for repayment, only the necessary amount is taken', async () => {
        // Mint some yDai the sneaky way
        await yDai1.orchestrate(owner, id('mint(address,uint256)'), { from: owner })
        await yDai1.mint(user1, 1, { from: owner }) // 1 extra yDai wei
        const yDaiTokens = addBN(daiTokens1, 1) // daiTokens1 + 1 wei

        assert.equal(await yDai1.balanceOf(user1), yDaiTokens.toString(), 'User1 does not have yDai')
        assert.equal(
          await controller.debtDai(CHAI, maturity1, user1),
          daiTokens1.toString(),
          'User1 does not have debt'
        )

        await yDai1.approve(treasury.address, yDaiTokens, { from: user1 })
        await controller.repayYDai(CHAI, maturity1, user1, user1, yDaiTokens, { from: user1 })

        assert.equal(await yDai1.balanceOf(user1), 1, 'User1 should have yDai left')
        assert.equal(await controller.debtDai(CHAI, maturity1, user1), 0, 'User1 should not have debt')
      })

      let rateIncrease: BigNumber
      let chiIncrease: BigNumber
      let chiDifferential: BigNumber
      let increasedDebt: BigNumber
      let debtIncrease: BigNumber
      let rate2: BigNumber
      let chi2: BigNumber

      describe('after maturity, with a chi increase', () => {
        beforeEach(async () => {
          assert.equal(await yDai1.balanceOf(user1), daiTokens1.toString(), 'User1 does not have yDai')
          assert.equal(
            await controller.debtDai(CHAI, maturity1, user1),
            daiTokens1.toString(),
            'User1 does not have debt'
          )
          // yDai matures
          await helper.advanceTime(1000)
          await helper.advanceBlock()
          await yDai1.mature()

          // Set rate to 1.75
          rateIncrease = toRay(0.5)
          rate2 = rate1.add(rateIncrease)
          await vat.fold(WETH, vat.address, rateIncrease, { from: owner })

          // Set chi to 1.5
          chiIncrease = toRay(0.25)
          chiDifferential = divRay(addBN(chi1, chiIncrease), chi1)
          chi2 = chi1.add(chiIncrease)
          await pot.setChi(chi2, { from: owner })

          increasedDebt = mulRay(daiTokens1, chiDifferential)
          debtIncrease = addBN(subBN(increasedDebt, daiTokens1), 1) // Rounding is different with JavaScript
        })

        it('as chi increases after maturity, so does the debt in when measured in dai', async () => {
          assert.equal(
            await controller.debtDai(CHAI, maturity1, user1),
            increasedDebt.toString(),
            'User1 should have ' +
              increasedDebt +
              ' debt after the chi change, instead has ' +
              (await controller.debtDai(CHAI, maturity1, user1))
          )
        })

        it("as chi increases after maturity, the debt doesn't in when measured in yDai", async () => {
          assert.equal(
            await controller.debtYDai(CHAI, maturity1, user1),
            daiTokens1.toString(),
            'User1 should have ' +
              daiTokens1 +
              ' debt after the chi change, instead has ' +
              (await controller.debtYDai(CHAI, maturity1, user1))
          )
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
          assert.equal(
            await controller.debtDai(CHAI, maturity1, user2),
            increasedDebt.toString(),
            'User2 should have ' +
              increasedDebt +
              ' Dai debt, instead has ' +
              (await controller.debtDai(CHAI, maturity1, user2))
          )
        })

        it('more Dai is required to repay after maturity as chi increases', async () => {
          await maker.getDai(user1, daiTokens1, rate2) // daiTokens1 is not going to be enough anymore
          await dai.approve(treasury.address, daiTokens1, { from: user1 })
          await controller.repayDai(CHAI, maturity1, user1, user1, daiTokens1, { from: user1 })

          assert.equal(
            await controller.debtDai(CHAI, maturity1, user1),
            debtIncrease.toString(),
            'User1 should have ' +
              debtIncrease +
              ' dai debt, instead has ' +
              (await controller.debtDai(CHAI, maturity1, user1))
          )
        })
      })
    })
  })
})
