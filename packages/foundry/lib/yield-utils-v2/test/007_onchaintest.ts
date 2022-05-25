import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import ERC20MockArtifact from "../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json";
import OnChainTestArtifact from "../artifacts/contracts/utils/OnChainTest.sol/OnChainTest.json";
import { ERC20Mock as ERC20 } from "../typechain/ERC20Mock";

import { ethers, waffle } from "hardhat";
import { expect } from "chai";
import { OnChainTest } from "../typechain";
const { deployContract, loadFixture } = waffle;

describe("OnChainTest", async function () {
  let deployerAcc: SignerWithAddress;
  let deployer: string;
  let erc20: ERC20;
  let onChainTest: OnChainTest;

  before(async () => {
    const signers = await ethers.getSigners();

    deployerAcc = signers[0];
    deployer = await deployerAcc.getAddress();

    onChainTest = (await deployContract(
      deployerAcc,
      OnChainTestArtifact
    )) as OnChainTest;
    erc20 = (await deployContract(deployerAcc, ERC20MockArtifact, [
      "Test",
      "TST",
    ])) as ERC20;
  });

  describe("twoValuesEquator", async () => {
    it("Should be able to compare 2 value", async () => {
      await onChainTest.twoValuesEquator("0x11", "0x11");
    });
    it("Should fail if 2 values are unequal", async () => {
      await expect(
        onChainTest.twoValuesEquator("0x11", "0x12")
      ).to.be.revertedWith("Mismatched value");
    });
  });

  describe("twoCallsEquator", async () => {
    it("Should be able to compare 2 value received from 2 calls", async () => {
      await onChainTest.twoCallsEquator(
        erc20.address,
        erc20.address,
        erc20.interface.encodeFunctionData("decimals"),
        erc20.interface.encodeFunctionData("decimals")
      );
    });
    it("Should fail if 2 values are unequal", async () => {
      await expect(
        onChainTest.twoCallsEquator(
          erc20.address,
          erc20.address,
          erc20.interface.encodeFunctionData("decimals"),
          erc20.interface.encodeFunctionData("name")
        )
      ).revertedWith("Mismatched value");
    });
  });

  describe("valueAndCallEquator", async () => {
    it("Should be able to compare 2 value", async () => {
      await onChainTest.valueAndCallEquator(
        erc20.address,
        erc20.interface.encodeFunctionData("decimals"),
        "0x0000000000000000000000000000000000000000000000000000000000000012"
      );
    });
    it("Should fail if 2 values are unequal", async () => {
      await expect(
        onChainTest.valueAndCallEquator(
          erc20.address,
          erc20.interface.encodeFunctionData("decimals"),
          "0x0000000000000000000000000000000000000000000000000000000000000032"
        )
      ).to.be.revertedWith("Mismatched value");
    });
  });
});
