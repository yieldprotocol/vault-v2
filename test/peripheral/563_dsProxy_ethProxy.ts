// Peripheral
const EthProxy = artifacts.require('YieldProxy')
const DSProxy = artifacts.require('DSProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

// @ts-ignore
import { balance } from '@openzeppelin/test-helpers'
import { WETH, spot, wethTokens1, mulRay } from '../shared/utils'
import { Contract, YieldEnvironmentLite } from '../shared/fixtures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'

const SIGNATURE_TYPEHASH = keccak256(
  toUtf8Bytes('Signature(address user,address delegate,uint256 nonce,uint256 deadline)')
)

contract('YieldProxy - EthProxy', async (accounts) => {
  let [owner, user1, user2] = accounts

  let vat: Contract
  let controller: Contract
  let treasury: Contract
  let ethProxy: Contract
  let weth: Contract

  let proxyFactory: Contract
  let proxyRegistry: Contract
  let dsProxy: Contract

  beforeEach(async () => {
    const env = await YieldEnvironmentLite.setup([])
    controller = env.controller
    treasury = env.treasury
    vat = env.maker.vat
    weth = env.maker.weth

    // Setup EthProxy
    ethProxy = await EthProxy.new(env.controller.address, [])

    // Setup DSProxyFactory and DSProxyCache
    proxyFactory = await DSProxyFactory.new({ from: owner })

    // Setup DSProxyRegistry
    proxyRegistry = await DSProxyRegistry.new(proxyFactory.address, { from: owner })
  })

  describe('directly', () => {
    it('allows user to post eth', async () => {
      assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury has weth in MakerDAO')
      assert.equal(await controller.powerOf(WETH, user2), 0, 'User2 has borrowing power')

      const previousBalance = await balance.current(user1)
      await ethProxy.post(user2, { from: user1, value: wethTokens1 })

      expect(await balance.current(user1)).to.be.bignumber.lt(previousBalance)
      assert.equal((await vat.urns(WETH, treasury.address)).ink, wethTokens1, 'Treasury should have weth in MakerDAO')
      assert.equal(
        await controller.powerOf(WETH, user2),
        mulRay(wethTokens1, spot).toString(),
        'User2 should have ' +
          mulRay(wethTokens1, spot) +
          ' borrowing power, instead has ' +
          (await controller.powerOf(WETH, user2))
      )
    })

    describe('with posted eth', () => {
      beforeEach(async () => {
        await ethProxy.post(user1, { from: user1, value: wethTokens1 })

        assert.equal(
          (await vat.urns(WETH, treasury.address)).ink,
          wethTokens1,
          'Treasury does not have weth in MakerDAO'
        )
        assert.equal(
          await controller.powerOf(WETH, user1),
          mulRay(wethTokens1, spot).toString(),
          'User1 does not have borrowing power'
        )
        assert.equal(await weth.balanceOf(user2), 0, 'User2 has collateral in hand')
      })

      it('allows user to withdraw weth', async () => {
        await controller.addDelegate(ethProxy.address, { from: user1 })
        const previousBalance = await balance.current(user2)
        await ethProxy.withdraw(user2, wethTokens1, { from: user1 })

        expect(await balance.current(user2)).to.be.bignumber.gt(previousBalance)
        assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury should not not have weth in MakerDAO')
        assert.equal(await controller.powerOf(WETH, user1), 0, 'User1 should not have borrowing power')
      })
    })
  })

  describe('through dsproxy', () => {
    beforeEach(async () => {
      // Sets DSProxy for user1
      await proxyRegistry.build({ from: user1 })
      dsProxy = await DSProxy.at(await proxyRegistry.proxies(user1))
      await controller.addDelegate(dsProxy.address, { from: user1 })
    })

    it('allows user to post eth', async () => {
      assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury has weth in MakerDAO')
      assert.equal(await controller.powerOf(WETH, user2), 0, 'User2 has borrowing power')

      const previousBalance = await balance.current(user1)

      const calldata = ethProxy.contract.methods.post(user2).encodeABI()
      await dsProxy.methods['execute(address,bytes)'](ethProxy.address, calldata, { from: user1, value: wethTokens1 })

      expect(await balance.current(user1)).to.be.bignumber.lt(previousBalance)
      assert.equal((await vat.urns(WETH, treasury.address)).ink, wethTokens1, 'Treasury should have weth in MakerDAO')
      assert.equal(
        await controller.powerOf(WETH, user2),
        mulRay(wethTokens1, spot).toString(),
        'User2 should have ' +
          mulRay(wethTokens1, spot) +
          ' borrowing power, instead has ' +
          (await controller.powerOf(WETH, user2))
      )
    })

    describe('with posted eth', () => {
      beforeEach(async () => {
        await ethProxy.post(user1, { from: user1, value: wethTokens1 })
      })

      it('allows user to withdraw weth', async () => {
        const previousBalance = await balance.current(user2)

        const calldata = ethProxy.contract.methods.withdraw(user2, wethTokens1).encodeABI()
        await dsProxy.methods['execute(address,bytes)'](ethProxy.address, calldata, { from: user1 })

        expect(await balance.current(user2)).to.be.bignumber.gt(previousBalance)
        assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury should not not have weth in MakerDAO')
        assert.equal(await controller.powerOf(WETH, user1), 0, 'User1 should not have borrowing power')
      })
    })
  })
})
