const Delegable = artifacts.require("Delegable");

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers';
import { Contract } from "./shared/fixtures"
import {
  keccak256,
  defaultAbiCoder,
  toUtf8Bytes,
  solidityPack
} from 'ethers/lib/utils'
import { ecsign } from 'ethereumjs-util'

const SIGNATURE_TYPEHASH = keccak256(toUtf8Bytes('Signature(address user,address delegate,uint256 nonce,uint256 deadline)'));

contract('Delegable with signatures', async (accounts: string[]) =>  {
    // this is the first account that buidler creates
    // https://github.com/nomiclabs/buidler/blob/d399a60452f80a6e88d974b2b9205f4894a60d29/packages/buidler-core/src/internal/core/config/default-config.ts#L41
    const ownerPrivateKey = Buffer.from("c5e8f61d1ab959b397eecc0a37a6517b8e67a0e7cf1f4bce5591f3ed80199122", 'hex')
    const chainId = 31337; // buidlerevm chain id

    let [ owner, user1, delegate1 ] = accounts;

    let delegableContract: Contract;
    let name: string;

    beforeEach(async() => {
        delegableContract = await Delegable.new({ from: owner });
        name = 'Yield';
    })

    it('initializes SIGNATURE_TYPEHASH correctly', async () => {
        assert.equal(await delegableContract.SIGNATURE_TYPEHASH(), SIGNATURE_TYPEHASH)
    })

    it('initializes DELEGABLE_DOMAIN correctly', async () => {
      assert.equal(
          await delegableContract.DELEGABLE_DOMAIN(),
          getDomainSeparator(name, delegableContract.address, chainId)
      );
  })

    it('permits and emits Delegate (replay safe)', async() => {
        // Create the signature request
        const signature = {
            user: user1,
            delegate: delegate1,
        };

        // deadline as much as you want in the future
        const deadline = 100000000000000;

        // Get the user's signatureCount
        const signatureCount = await delegableContract.signatureCount(user1);

        // Get the EIP712 digest
        const digest = getPermitDigest(name, delegableContract.address, chainId, signature, signatureCount, deadline);

        // Sign it
        // NOTE: Using web3.eth.sign will hash the message internally again which
        // we do not want, so we're manually signing here
        const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), ownerPrivateKey)

        // Approve it
        const receipt = await delegableContract.addDelegateBySignature(signature.user, signature.delegate, deadline, v, r, s, { from: user1 });
        const event = receipt.logs[0];

        // It worked!
        assert.equal(
            event.event,
            "Delegate",
        );
        assert.equal(
            await delegableContract.signatureCount(user1),
            1
        );
        assert.equal(
            await delegableContract.delegated(signature.user, signature.delegate),
            true,
        );

        // Re-using the same sig doesn't work since the nonce has been incremented
        // on the contract level for replay-protection
        await expectRevert(
            delegableContract.addDelegateBySignature(signature.user, signature.delegate, deadline, v, r, s),
            "Delegable: Invalid signature",
        )

        // invalid ecrecover's return address(0x0), so we must also guarantee that
        // this case fails
        await expectRevert(
            delegableContract.addDelegateBySignature("0x0000000000000000000000000000000000000000", signature.delegate, deadline, "0x99", r, s),
            "Delegable: Invalid signature",
        )
    })
})

// Returns the EIP712 hash which should be signed by the user
// in order to make a call to `permit`
function getPermitDigest(
  name: string,
  address: string,
  chainId: number,
  signature: {
      user: string,
      delegate: string,
  },
  signatureCount: number,
  deadline: number,
) {
  const DELEGABLE_DOMAIN = getDomainSeparator(name, address, chainId)
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DELEGABLE_DOMAIN,
        keccak256(
          defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256'],
            [SIGNATURE_TYPEHASH, signature.user, signature.delegate, signatureCount, deadline]
          )
        )
      ]
    )
  )
}

// Gets the EIP712 domain separator
function getDomainSeparator(name: string, contractAddress: string, chainId: number) {
  return keccak256(
    defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
        keccak256(toUtf8Bytes(name)),
        keccak256(toUtf8Bytes('1')),
        chainId,
        contractAddress
      ]
    )
  )
}

