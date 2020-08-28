import { id } from 'ethers/lib/utils'
// @ts-ignore
import helper from 'ganache-time-traveler'
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers'
import {
  rate1,
  daiDebt1,
  WETH,
  daiTokens1,
  wethTokens1,
  chaiTokens1,
  spot,
  toRay,
  mulRay,
  divRay,
  bnify,
  almostEqual,
  precision,
} from './shared/utils'
import { YieldEnvironment, Contract } from './shared/fixtures'
import { assert, expect } from 'chai'

contract('Unwind - Treasury', async (accounts) => {
  let [owner, user] = accounts

  let snapshot: any
  let snapshotId: string

  let env: YieldEnvironment

  let dai: Contract
  let vat: Contract
  let controller: Contract
  let treasury: Contract
  let weth: Contract
  let liquidations: Contract
  let unwind: Contract
  let end: Contract
  let chai: Contract

  let maturity1: number
  let maturity2: number

  const tag = divRay(toRay(0.9), spot)
  const treasuryDebt = mulRay(wethTokens1, spot).sub(1000) // No need to max out the debt of the Treasury to the last wei
  const taggedWeth = mulRay(treasuryDebt, tag)
  const fix = divRay(toRay(1.1), spot)
  const fixedWeth = mulRay(treasuryDebt, fix)

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    env = await YieldEnvironment.setup([])
    controller = env.controller
    treasury = env.treasury
    liquidations = env.liquidations
    unwind = env.unwind

    vat = env.maker.vat
    dai = env.maker.dai
    weth = env.maker.weth
    end = env.maker.end
    chai = env.maker.chai

    // Allow owner to interact directly with Treasury, not for production
    const treasuryFunctions = ['pushDai', 'pullDai', 'pushChai', 'pullChai', 'pushWeth', 'pullWeth'].map((func) =>
      id(func + '(address,uint256)')
    )
    await treasury.batchOrchestrate(owner, treasuryFunctions)
    await end.rely(owner, { from: owner }) // `owner` replaces MKR governance
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  describe('with posted weth', () => {
    beforeEach(async () => {
      await weth.deposit({ from: owner, value: wethTokens1 })
      await weth.approve(treasury.address, wethTokens1, { from: owner })
      await treasury.pushWeth(owner, wethTokens1, { from: owner })

      assert.equal(
        (await vat.urns(WETH, treasury.address)).ink,
        wethTokens1,
        'Treasury should have ' + wethTokens1 + ' weth wei as collateral'
      )
    })

    it('does not allow to unwind if MakerDAO is live', async () => {
      await expectRevert(unwind.unwind({ from: owner }), 'Unwind: MakerDAO not shutting down')
    })

    describe('with Dss unwind initiated and tag defined', () => {
      beforeEach(async () => {
        await end.cage({ from: owner })
        await end.setTag(WETH, tag, { from: owner })
      })

      it('allows to unwind', async () => {
        await unwind.unwind({ from: owner })

        assert.equal(await unwind.live(), false, 'Unwind should be activated')
        assert.equal(await treasury.live(), false, 'Treasury should not be live')
        assert.equal(await controller.live(), false, 'Controller should not be live')
        assert.equal(await liquidations.live(), false, 'Liquidations should not be live')
      })

      describe('with yDai in unwind', () => {
        beforeEach(async () => {
          await unwind.unwind({ from: owner })
        })

        it('allows to free system collateral without debt', async () => {
          await unwind.settleTreasury({ from: owner })

          assert.equal(
            await weth.balanceOf(unwind.address, { from: owner }),
            wethTokens1,
            'Treasury should have ' +
              wethTokens1 +
              ' weth in hand, instead has ' +
              (await weth.balanceOf(unwind.address, { from: owner }))
          )
        })

        it('does not allow to push or pull assets', async () => {
          await expectRevert(
            treasury.pushWeth(user, wethTokens1, { from: owner }),
            'Treasury: Not available during unwind'
          )
          await expectRevert(
            treasury.pushChai(user, chaiTokens1, { from: owner }),
            'Treasury: Not available during unwind'
          )
          await expectRevert(
            treasury.pushDai(user, daiTokens1, { from: owner }),
            'Treasury: Not available during unwind'
          )
          await expectRevert(treasury.pullWeth(owner, 1, { from: owner }), 'Treasury: Not available during unwind')
          await expectRevert(treasury.pullChai(owner, 1, { from: owner }), 'Treasury: Not available during unwind')
          await expectRevert(treasury.pullDai(owner, 1, { from: owner }), 'Treasury: Not available during unwind')
        })
      })
    })

    describe('with debt', () => {
      beforeEach(async () => {
        await treasury.pullDai(owner, treasuryDebt, { from: owner })
        expect((await vat.urns(WETH, treasury.address)).art).to.be.bignumber.gt(new BN('0'))
        expect(await treasury.debt()).to.be.bignumber.gt(new BN('0'))

        // Adding some extra unlocked collateral
        await weth.deposit({ from: owner, value: 1 })
        await weth.approve(treasury.address, 1, { from: owner })
        await treasury.pushWeth(owner, 1, { from: owner })
      })

      describe('with unwind initiated', () => {
        beforeEach(async () => {
          await end.cage({ from: owner })
          await end.setTag(WETH, tag, { from: owner })
          await unwind.unwind({ from: owner })
        })

        it('allows to settle treasury debt', async () => {
          await unwind.settleTreasury({ from: owner })

          almostEqual(
            await weth.balanceOf(unwind.address, { from: owner }),
            bnify(wethTokens1).sub(taggedWeth).toString(),
            precision
          )
        })
      })
    })

    describe('with savings', () => {
      beforeEach(async () => {
        await env.maker.getDai(owner, daiTokens1, rate1)

        await dai.approve(treasury.address, daiTokens1, { from: owner })
        await treasury.pushDai(owner, daiTokens1, { from: owner })

        assert.equal(
          await chai.balanceOf(treasury.address),
          chaiTokens1,
          'Treasury should have ' + daiTokens1 + ' savings (as chai).'
        )
      })

      describe('with Dss unwind initiated and fix defined', () => {
        beforeEach(async () => {
          await env.maker.getDai(user, bnify(daiTokens1).mul(2), rate1)

          await end.cage({ from: owner })
          await end.setTag(WETH, tag, { from: owner })
          await end.setDebt(1, { from: owner })
          await end.setFix(WETH, fix, { from: owner })

          // Settle some random guy's debt for end.sol to have weth
          await end.skim(WETH, user, { from: user })

          await unwind.unwind({ from: owner })
        })

        it('allows to cash dai for weth', async () => {
          assert.equal(await vat.gem(WETH, unwind.address), 0, 'Unwind should have no weth in WethJoin')

          await unwind.cashSavings({ from: owner })

          // Fun fact, MakerDAO rounds in your favour when determining how much collateral to take to settle your debt.
          assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury should have no savings (as chai).')
          almostEqual(
            await weth.balanceOf(unwind.address, { from: owner }),
            fixedWeth.toString(),
            precision // We are off by more than the usual precision here, not a big deal
          )
        })
      })
    })
  })
})
