import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
// @ts-ignore
import {
  PERMIT_TYPEHASH,
  getPermitDigest,
  getDomainSeparator,
  sign,
  privateKey0,
} from "../src/signatures";

import ERC20MockArtifact from "../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json";

import { ERC20Mock as ERC20 } from "../typechain/ERC20Mock";

import { ethers, waffle, network } from "hardhat";
import { expect } from "chai";
const { deployContract } = waffle;

const chainId = 31337; // buidlerevm chain id

let ownerAcc: SignerWithAddress;
let owner: string;
let userAcc: SignerWithAddress;
let user: string;

let erc20: ERC20;
let name: string;

describe("ERC20Permit", function () {
  this.timeout(0);

  before(async () => {
    const signers = await ethers.getSigners();

    ownerAcc = signers[0];
    owner = await ownerAcc.getAddress();

    userAcc = signers[1];
    user = await userAcc.getAddress();
  });

  beforeEach(async () => {
    erc20 = (await deployContract(ownerAcc, ERC20MockArtifact, [
      "Test",
      "TST",
    ])) as ERC20;
    name = await erc20.name();
  });

  it("initializes DOMAIN_SEPARATOR and PERMIT_TYPEHASH correctly", async () => {
    expect(await erc20.PERMIT_TYPEHASH()).to.be.equal(PERMIT_TYPEHASH);
    expect(await erc20.DOMAIN_SEPARATOR()).to.be.equal(
      getDomainSeparator(name, erc20.address, await erc20.version(), chainId)
    );
  });

  it("permits and emits Approval (replay safe)", async () => {
    // Create the approval request
    const approve = {
      owner: owner,
      spender: user,
      value: 100,
    };

    // deadline as much as you want in the future
    const deadline = Math.floor(Date.now()) + 1000;

    // Get the user's nonce
    const nonce = await erc20.nonces(owner);

    // Get the EIP712 digest
    const digest = getPermitDigest(
      await erc20.DOMAIN_SEPARATOR(),
      approve,
      nonce,
      deadline
    );

    // Sign it
    // NOTE: Using web3.eth.sign will hash the message internally again which
    // we do not want, so we're manually signing here
    const { v, r, s } = sign(digest, privateKey0);

    // Approve and check it
    expect(
      await erc20.permit(
        approve.owner,
        approve.spender,
        approve.value,
        deadline,
        v,
        r,
        s
      )
    ).to.emit(erc20, "Approval");
    expect(await erc20.nonces(owner)).to.be.equal(1);
    expect(await erc20.allowance(approve.owner, approve.spender)).to.be.equal(
      approve.value
    );

    // Re-using the same sig doesn't work since the nonce has been incremented
    // on the contract level for replay-protection
    await expect(
      erc20.permit(
        approve.owner,
        approve.spender,
        approve.value,
        deadline,
        v,
        r,
        s
      )
    ).to.be.revertedWith("ERC20Permit: invalid signature");

    // invalid ecrecover's return address(0x0), so we must also guarantee that
    // this case fails
    await expect(
      erc20.permit(
        "0x0000000000000000000000000000000000000000",
        approve.spender,
        approve.value,
        deadline,
        "0x99",
        r,
        s
      )
    ).to.be.revertedWith("ERC20Permit: invalid signature");
  });
});
