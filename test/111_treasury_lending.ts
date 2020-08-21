// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { MakerEnvironment, Contract } from './shared/fixtures'
import { WETH, daiDebt1, daiTokens1, wethTokens1, chaiTokens1 } from './shared/utils'

contract('Treasury - Lending', async (accounts: string[]) => {
  let [owner, user] = accounts

  let treasury: Contract
  let vat: Contract
  let weth: Contract
  let wethJoin: Contract
  let chai: Contract
  let dai: Contract

  beforeEach(async () => {
    const maker = await MakerEnvironment.setup()
    treasury = await maker.setupTreasury()
    vat = maker.vat
    weth = maker.weth
    wethJoin = maker.wethJoin
    chai = maker.chai
    dai = maker.dai

    // Setup tests - Allow owner to interact directly with Treasury, not for production
    treasury.orchestrate(owner, { from: owner })
  })

  it('get the size of the contract', async () => {
    console.log()
    console.log('    ·--------------------|------------------|------------------|------------------·')
    console.log('    |  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |')
    console.log('    ·····················|··················|··················|···················')

    const bytecode = treasury.constructor._json.bytecode
    const deployed = treasury.constructor._json.deployedBytecode
    const sizeOfB = bytecode.length / 2
    const sizeOfD = deployed.length / 2
    const sizeOfC = sizeOfB - sizeOfD
    console.log(
      '    |  ' +
        treasury.constructor._json.contractName.padEnd(18, ' ') +
        '|' +
        ('' + sizeOfB).padStart(16, ' ') +
        '  ' +
        '|' +
        ('' + sizeOfD).padStart(16, ' ') +
        '  ' +
        '|' +
        ('' + sizeOfC).padStart(16, ' ') +
        '  |'
    )
    console.log('    ·--------------------|------------------|------------------|------------------·')
    console.log()
  })

  it('should fail for failed weth transfers', async () => {
    // Let's check how WETH is implemented, maybe we can remove this one.
  })

  it('allows to post collateral', async () => {
    assert.equal(await weth.balanceOf(wethJoin.address), web3.utils.toWei('0'))

    await weth.deposit({ from: owner, value: wethTokens1 })
    await weth.approve(treasury.address, wethTokens1, { from: owner })
    await treasury.pushWeth(owner, wethTokens1, { from: owner })

    // Test transfer of collateral
    assert.equal(await weth.balanceOf(wethJoin.address), wethTokens1.toString())

    // Test collateral registering via `frob`
    assert.equal((await vat.urns(WETH, treasury.address)).ink, wethTokens1.toString())
  })

  describe('with posted collateral', () => {
    beforeEach(async () => {
      await weth.deposit({ from: owner, value: wethTokens1 })
      await weth.approve(treasury.address, wethTokens1, { from: owner })
      await treasury.pushWeth(owner, wethTokens1, { from: owner })
    })

    it('returns borrowing power', async () => {
      assert.equal(
        await treasury.power(),
        daiTokens1.toString(),
        'Should return posted collateral * collateralization ratio'
      )
    })

    it('allows to withdraw collateral for user', async () => {
      assert.equal(await weth.balanceOf(user), 0)

      await treasury.pullWeth(user, wethTokens1, { from: owner })

      // Test transfer of collateral
      assert.equal(await weth.balanceOf(user), wethTokens1.toString())

      // Test collateral registering via `frob`
      assert.equal((await vat.urns(WETH, treasury.address)).ink, 0)
    })

    it('pulls dai borrowed from MakerDAO for user', async () => {
      // Test with two different stability rates, if possible.
      await treasury.pullDai(user, daiTokens1, { from: owner })

      assert.equal(await dai.balanceOf(user), daiTokens1.toString())
      assert.equal((await vat.urns(WETH, treasury.address)).art, daiDebt1.toString())
    })

    it('pulls chai converted from dai borrowed from MakerDAO for user', async () => {
      // Test with two different stability rates, if possible.
      await treasury.pullChai(user, chaiTokens1, { from: owner })

      assert.equal(await chai.balanceOf(user), chaiTokens1.toString())
      assert.equal((await vat.urns(WETH, treasury.address)).art, daiDebt1.toString())
    })

    it("shouldn't allow borrowing beyond power", async () => {
      await treasury.pullDai(user, daiTokens1, { from: owner })
      assert.equal(
        await treasury.power(),
        daiTokens1.toString(),
        'We should have ' + daiTokens1 + ' dai borrowing power.'
      )
      assert.equal(await treasury.debt(), daiTokens1.toString(), 'We should have ' + daiTokens1 + ' dai debt.')
      await expectRevert(
        treasury.pullDai(user, 1, { from: owner }), // Not a wei more borrowing
        'Vat/not-safe'
      )
    })

    describe('with a dai debt towards MakerDAO', () => {
      beforeEach(async () => {
        await treasury.pullDai(user, daiTokens1, { from: owner })
      })

      it('returns treasury debt', async () => {
        assert.equal(await treasury.debt(), daiTokens1.toString(), 'Should return borrowed dai')
      })

      it('pushes dai that repays debt towards MakerDAO', async () => {
        // Test `normalizedAmount >= normalizedDebt`
        await dai.approve(treasury.address, daiTokens1, { from: user })
        await treasury.pushDai(user, daiTokens1, { from: owner })

        assert.equal(await dai.balanceOf(user), 0)
        assert.equal((await vat.urns(WETH, treasury.address)).art, 0)
        assert.equal(await vat.dai(treasury.address), 0)
      })

      it('pushes chai that repays debt towards MakerDAO', async () => {
        await dai.approve(chai.address, daiTokens1, { from: user })
        await chai.join(user, daiTokens1, { from: user })
        await chai.approve(treasury.address, chaiTokens1, { from: user })
        await treasury.pushChai(user, chaiTokens1, { from: owner })

        assert.equal(await dai.balanceOf(user), 0)
        assert.equal((await vat.urns(WETH, treasury.address)).art, 0)
        assert.equal(await vat.dai(treasury.address), 0)
      })
    })
  })
})
