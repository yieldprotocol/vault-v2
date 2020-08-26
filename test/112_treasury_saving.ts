import { id } from 'ethers/lib/utils'
import { YieldEnvironment, MakerEnvironment, Contract } from './shared/fixtures'
import { chi1, rate1, daiTokens1, chaiTokens1, almostEqual, divRay } from './shared/utils'

contract('Treasury - Saving', async (accounts) => {
  let [owner, user] = accounts

  let treasury: Contract
  let chai: Contract
  let dai: Contract

  const precision = 1000

  beforeEach(async () => {
    const maker = await MakerEnvironment.setup()
    treasury = await YieldEnvironment.setupTreasury(maker)
    chai = maker.chai
    dai = maker.dai

    // Setup tests - Allow owner to interact directly with Treasury, not for production
    const treasuryFunctions = ['pushDai', 'pullDai', 'pushChai', 'pullChai', 'pushWeth', 'pullWeth'].map(func => id(func + '(address,uint256)'))
    await treasury.batchOrchestrate(owner, treasuryFunctions)

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
    almostEqual(await treasury.savings(), daiTokens1.toString(), precision)
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
    almostEqual(await treasury.savings(), daiTokens1.toString(), precision)
    assert.equal(await chai.balanceOf(user), 0, 'User should not have chai')
  })

  describe('with savings', () => {
    beforeEach(async () => {
      await dai.approve(treasury.address, daiTokens1, { from: user })
      await treasury.pushDai(user, daiTokens1, { from: owner })
    })

    it('pulls dai from savings', async () => {
      assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury does not have chai')
      almostEqual(await treasury.savings(), daiTokens1.toString(), precision)
      assert.equal(await dai.balanceOf(user), 0, 'User has dai')

      const toPull = await treasury.savings()
      await treasury.pullDai(user, toPull, { from: owner })

      assert.equal(await chai.balanceOf(treasury.address), 0, 'Treasury should not have chai')
      almostEqual(await treasury.savings(), 0, precision)
      assert.equal(await dai.balanceOf(user), toPull.toString(), 'User should have dai')
    })

    it('pulls chai from savings', async () => {
      assert.equal(await chai.balanceOf(treasury.address), chaiTokens1.toString(), 'Treasury does not have chai')
      almostEqual(await treasury.savings(), daiTokens1.toString(), precision)
      assert.equal(await dai.balanceOf(user), 0, 'User has dai')

      const toPull = divRay((await treasury.savings()).toString(), chi1)
      await treasury.pullChai(user, toPull, { from: owner })

      almostEqual(await chai.balanceOf(treasury.address), 0, precision)
      almostEqual(await treasury.savings(), 0, precision)
      assert.equal(await chai.balanceOf(user), toPull.toString(), 'User should have chai')
    })
  })
})
