const ERC20 = artifacts.require("TestERC20");
const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');
const {
  keccak256,
  defaultAbiCoder,
  toUtf8Bytes,
  solidityPack
} = require('ethers/utils')
const { ecsign } = require('ethereumjs-util')



const PERMIT_TYPEHASH = keccak256(toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'));

contract('ERC20Permit', async (accounts) =>  {
    // this is the first account that buidler creates
    // https://github.com/nomiclabs/buidler/blob/d399a60452f80a6e88d974b2b9205f4894a60d29/packages/buidler-core/src/internal/core/config/default-config.ts#L41
    const ownerPrivateKey = Buffer.from("c5e8f61d1ab959b397eecc0a37a6517b8e67a0e7cf1f4bce5591f3ed80199122", 'hex')

    let [ owner, user ] = accounts;
    let token;
    let chainId;
    let name;


    beforeEach(async() => {
        token = await ERC20.new(1000, { from: owner });
        chainId = await web3.eth.getChainId();
        name = await token.name();

    })

    it('initializes DOMAIN_SEPARATOR and PERMIT_TYPEHASH correctly', async () => {
        assert.equal(await token.PERMIT_TYPEHASH(), PERMIT_TYPEHASH)

        assert.equal(
            await token.DOMAIN_SEPARATOR(),
            getDomainSeparator(name, token.address, chainId)
        );
    })

    it('permits and emits Approval (replay safe)', async() => {
        // Create the approval request
        const approve = {
            owner: owner,
            spender: user,
            value: 100
        };

        // deadline as much as you want in the future
        const deadline = 100000000000000;

        // Get the user's nonce
        const nonce = await token.nonces(owner);

        // Get the EIP712 digest
        const digest = getPermitDigest(name, token.address, chainId, approve, nonce, deadline);

        // Sign it
        // NOTE: Using web3.eth.sign will hash the message internally again which
        // we do not want, so we're manually signing here
        const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), ownerPrivateKey)

        // Approve it
        const receipt = await token.permit(approve.owner, approve.spender, approve.value, deadline, v, r, s);
        const event = receipt.logs[0];

        // It worked!
        assert.equal(
            event.event,
            "Approval",
        );
        assert.equal(
            await token.nonces(owner),
            1
        );
        assert.equal(
            await token.allowance(approve.owner, approve.spender),
            approve.value,
        );

        // Re-using the same sig doesn't work since the nonce has been incremented
        // on the contract level for replay-protection
        await expectRevert(
            token.permit(approve.owner, approve.spender, approve.value, deadline, v, r, s),
            "ERC20Permit: invalid signature",
        )

        // invalid ecrecover's return address(0x0), so we must also guarantee that
        // this case fails
        await expectRevert(
            token.permit("0x0000000000000000000000000000000000000000", approve.spender, approve.value, deadline, "0x99", r, s),
            "ERC20Permit: invalid signature",
        )
    })
})

// Returns the EIP712 hash which should be signed by the user
// in order to make a call to `permit`
function getPermitDigest(
  name,
  address,
  chainId,
  approve,
  nonce,
  deadline
) {
  const DOMAIN_SEPARATOR = getDomainSeparator(name, address, chainId)
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
        keccak256(
          defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
            [PERMIT_TYPEHASH, approve.owner, approve.spender, approve.value, nonce.toNumber(), deadline]
          )
        )
      ]
    )
  )
}

// Gets the EIP712 domain separator
function getDomainSeparator(name, tokenAddress, chainId) {
  return keccak256(
    defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
        keccak256(toUtf8Bytes(name)),
        keccak256(toUtf8Bytes('1')),
        chainId,
        tokenAddress
      ]
    )
  )
}

