import { MakerEnvironment, Contract } from './shared/fixtures'
import { rate1, daiTokens1, chaiTokens1 } from './shared/utils'

contract('Treasury - Saving', async (accounts) => {
  let [owner, user] = accounts

  let treasury: Contract
  let chai: Contract
  let dai: Contract

  beforeEach(async () => {
    const maker = await MakerEnvironment.setup()
    treasury = await maker.setupTreasury()
    chai = maker.chai
    dai = maker.dai

    // Setup tests - Allow owner to interact directly with Treasury, not for production
    await treasury.orchestrate(owner, { from: owner })

    // Borrow some dai
    await maker.getDai(user, daiTokens1, rate1)
  })

  it('allows to save dai', async () => {
    assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury has chai')
    assert.equal(await treasury.savings(), 0, 'Treasury has savings in dai units')
    assert.equal(await dai.balanceOf(user), daiTokens1.toString(), 'User does not have dai')

    await dai.approve(treasury.address, daiTokens1, { from: user })
    await treasury.pushDai(user, daiTokens1, { from: owner })

    // Test transfer of collateral
    assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury should have chai')
    assert.equal(
      await treasury.savings(),
      daiTokens1.toString(),
      'Treasury should have ' + daiTokens1 + ' savings in dai units, instead has ' + (await treasury.savings())
    )
    assert.equal(await dai.balanceOf(user), 0, 'User should not have dai')
  })

  it('allows to save chai', async () => {
    assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury has chai')
    assert.equal(await treasury.savings(), 0, 'Treasury has savings in dai units')
    assert.equal(await dai.balanceOf(user), daiTokens1.toString(), 'User does not have dai')

    await dai.approve(chai.address, daiTokens1, { from: user })
    await chai.join(user, daiTokens1, { from: user })
    await chai.approve(treasury.address, chaiTokens1, { from: user })
    await treasury.pushChai(user, chaiTokens1, { from: owner })

    // Test transfer of collateral
    assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury should have chai')
    assert.equal(await treasury.savings(), daiTokens1.toString(), 'Treasury should report savings in dai units')
    assert.equal(await chai.balanceOf(user), 0, 'User should not have chai')
  })

  describe('with savings', () => {
    beforeEach(async () => {
      await dai.approve(treasury.address, daiTokens1, { from: user })
      await treasury.pushDai(user, daiTokens1, { from: owner })
    })

    it('pulls dai from savings', async () => {
      assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury does not have chai')
      assert.equal(await treasury.savings(), daiTokens1.toString(), 'Treasury does not report savings in dai units')
      assert.equal(await dai.balanceOf(user), 0, 'User has dai')

      await treasury.pullDai(user, daiTokens1, { from: owner })

      assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury should not have chai')
      assert.equal(await treasury.savings(), 0, 'Treasury should not have savings in dai units')
      assert.equal(await dai.balanceOf(user), daiTokens1.toString(), 'User should have dai')
    })

    it('pulls chai from savings', async () => {
      assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury does not have chai')
      assert.equal(await treasury.savings(), daiTokens1.toString(), 'Treasury does not report savings in dai units')
      assert.equal(await dai.balanceOf(user), 0, 'User has dai')

      await treasury.pullChai(user, chaiTokens1, { from: owner })

      assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury should not have chai')
      assert.equal(await treasury.savings(), 0, 'Treasury should not have savings in dai units')
      assert.equal(await chai.balanceOf(user), chaiTokens1.toString(), 'User should have chai')
    })
  })
})
