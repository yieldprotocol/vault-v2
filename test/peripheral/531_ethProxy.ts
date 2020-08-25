// Peripheral
const EthProxy = artifacts.require('EthProxy')

// @ts-ignore
import helper from 'ganache-time-traveler'
// @ts-ignore
import { balance } from '@openzeppelin/test-helpers'
import { WETH, daiTokens1, wethTokens1 } from '../shared/utils'
import { Contract, YieldEnvironmentLite } from '../shared/fixtures'
import { getSignatureDigest } from '../shared/signatures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { ecsign } from 'ethereumjs-util'

const SIGNATURE_TYPEHASH = keccak256(
  toUtf8Bytes('Signature(address user,address delegate,uint256 nonce,uint256 deadline)')
)

contract('Controller - EthProxy', async (accounts) => {
  let [owner, user1, user2] = accounts

  // this is the SECOND account that buidler creates
  // https://github.com/nomiclabs/buidler/blob/d399a60452f80a6e88d974b2b9205f4894a60d29/packages/buidler-core/src/internal/core/config/default-config.ts#L46
  const userPrivateKey = Buffer.from('d49743deccbccc5dc7baa8e69e5be03298da8688a15dd202e20f15d5e0e9a9fb', 'hex')
  const chainId = 31337 // buidlerevm chain id
  const name = 'Yield'

  let snapshot: any
  let snapshotId: string

  let vat: Contract
  let controller: Contract
  let treasury: Contract
  let ethProxy: Contract
  let weth: Contract

  let maturity1: number
  let maturity2: number

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup yDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000
    maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000

    const env = await YieldEnvironmentLite.setup([maturity1, maturity2])
    controller = env.controller
    treasury = env.treasury
    vat = env.maker.vat
    weth = env.maker.weth

    // Setup EthProxy
    ethProxy = await EthProxy.new(weth.address, treasury.address, controller.address, { from: owner })
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  it('allows user to post eth', async () => {
    assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury has weth in MakerDAO')
    assert.equal(await controller.powerOf(WETH, user2), 0, 'User2 has borrowing power')

    const previousBalance = await balance.current(user1)
    await ethProxy.post(user2, wethTokens1, { from: user1, value: wethTokens1 })

    expect(await balance.current(user1)).to.be.bignumber.lt(previousBalance)
    assert.equal(
      (await vat.urns(WETH, treasury.address)).ink,
      wethTokens1.toString(),
      'Treasury should have weth in MakerDAO'
    )
    assert.equal(
      await controller.powerOf(WETH, user2),
      daiTokens1.toString(),
      'User2 should have ' + daiTokens1 + ' borrowing power, instead has ' + (await controller.powerOf(WETH, user2))
    )
  })

  describe('with posted eth', () => {
    beforeEach(async () => {
      await ethProxy.post(user1, wethTokens1, { from: user1, value: wethTokens1 })

      assert.equal(
        (await vat.urns(WETH, treasury.address)).ink,
        wethTokens1.toString(),
        'Treasury does not have weth in MakerDAO'
      )
      assert.equal(await controller.powerOf(WETH, user1), daiTokens1.toString(), 'User1 does not have borrowing power')
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

    it('allows user to withdraw weth with an encoded signature', async () => {
      // Create the signature request
      const signature = {
        user: user1,
        delegate: ethProxy.address,
      }

      // deadline as much as you want in the future
      const deadline = 100000000000000

      // Get the user's signatureCount
      const signatureCount = await controller.signatureCount(user1)

      // Get the EIP712 digest
      const digest = getSignatureDigest(
        SIGNATURE_TYPEHASH,
        name,
        controller.address,
        chainId,
        signature,
        signatureCount,
        deadline
      )

      // Sign it
      // NOTE: Using web3.eth.sign will hash the message internally again which
      // we do not want, so we're manually signing here
      const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), userPrivateKey)

      const previousBalance = await balance.current(user2)
      await ethProxy.withdrawBySignature(user2, wethTokens1, deadline, v, r, s, { from: user1 })

      expect(await balance.current(user2)).to.be.bignumber.gt(previousBalance)
      assert.equal((await vat.urns(WETH, treasury.address)).ink, 0, 'Treasury should not not have weth in MakerDAO')
      assert.equal(await controller.powerOf(WETH, user1), 0, 'User1 should not have borrowing power')
    })
  })
})
