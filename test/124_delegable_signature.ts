const Delegable = artifacts.require('Delegable')

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { Contract } from './shared/fixtures'
import { getSignatureDigest, getDomainSeparator } from './shared/signatures'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { ecsign } from 'ethereumjs-util'

const SIGNATURE_TYPEHASH = keccak256(
  toUtf8Bytes('Signature(address user,address delegate,uint256 nonce,uint256 deadline)')
)

contract('Delegable with signatures', async (accounts: string[]) => {
  // this is the SECOND account that buidler creates
  // https://github.com/nomiclabs/buidler/blob/d399a60452f80a6e88d974b2b9205f4894a60d29/packages/buidler-core/src/internal/core/config/default-config.ts#L46
  const userPrivateKey = Buffer.from('d49743deccbccc5dc7baa8e69e5be03298da8688a15dd202e20f15d5e0e9a9fb', 'hex')
  const chainId = 31337 // buidlerevm chain id

  let [owner, user, delegate] = accounts

  let delegableContract: Contract
  let name: string

  beforeEach(async () => {
    delegableContract = await Delegable.new({ from: owner })
    name = 'Yield'
  })

  it('initializes SIGNATURE_TYPEHASH correctly', async () => {
    assert.equal(await delegableContract.SIGNATURE_TYPEHASH(), SIGNATURE_TYPEHASH)
  })

  it('initializes DELEGABLE_DOMAIN correctly', async () => {
    assert.equal(
      await delegableContract.DELEGABLE_DOMAIN(),
      getDomainSeparator(name, delegableContract.address, chainId)
    )
  })

  it('permits and emits Delegate (replay safe)', async () => {
    // Create the signature request
    const signature = {
      user: user,
      delegate: delegate,
    }

    // deadline as much as you want in the future
    const deadline = 100000000000000

    // Get the user's signatureCount
    const signatureCount = await delegableContract.signatureCount(user)

    // Get the EIP712 digest
    const digest = getSignatureDigest(
      name,
      delegableContract.address,
      chainId,
      signature,
      signatureCount,
      deadline
    )

    // Sign it
    // NOTE: Using web3.eth.sign will hash the message internally again which
    // we do not want, so we're manually signing here
    const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), userPrivateKey)

    // Approve it
    const receipt = await delegableContract.addDelegateBySignature(
      signature.user,
      signature.delegate,
      deadline,
      v,
      r,
      s,
      { from: user }
    )
    const event = receipt.logs[0]

    // It worked!
    assert.equal(event.event, 'Delegate')
    assert.equal(await delegableContract.signatureCount(user), 1)
    assert.equal(await delegableContract.delegated(signature.user, signature.delegate), true)

    // Re-using the same sig doesn't work since the nonce has been incremented
    // on the contract level for replay-protection
    await expectRevert(
      delegableContract.addDelegateBySignature(signature.user, signature.delegate, deadline, v, r, s),
      'Delegable: Invalid signature'
    )

    // invalid ecrecover's return address(0x0), so we must also guarantee that
    // this case fails
    await expectRevert(
      delegableContract.addDelegateBySignature(
        '0x0000000000000000000000000000000000000000',
        signature.delegate,
        deadline,
        '0x99',
        r,
        s
      ),
      'Delegable: Invalid signature'
    )
  })
})
