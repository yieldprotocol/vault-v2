import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import ERC20MockArtifact from "../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json";

import { ERC20Mock as ERC20 } from "../typechain/ERC20Mock";

const MAX =
  "115792089237316195423570985008687907853269984665640564039457584007913129639935";

import { ethers, waffle } from "hardhat";
import { expect } from "chai";
const { deployContract } = waffle;

describe("ERC20", function () {
  this.timeout(0);

  let deployerAcc: SignerWithAddress;
  let deployer: string;
  let user1Acc: SignerWithAddress;
  let user1: string;
  let user2Acc: SignerWithAddress;
  let user2: string;
  let erc20: ERC20;

  before(async () => {
    const signers = await ethers.getSigners();

    deployerAcc = signers[0];
    deployer = await deployerAcc.getAddress();

    user1Acc = signers[1];
    user1 = await user1Acc.getAddress();

    user2Acc = signers[2];
    user2 = await user2Acc.getAddress();
  });

  beforeEach(async () => {
    erc20 = (await deployContract(deployerAcc, ERC20MockArtifact, [
      "Test",
      "TST",
    ])) as ERC20;
  });

  describe("deployment", async () => {
    it("returns the name", async () => {
      expect(await erc20.name()).to.be.equal("Test");
    });

    it("mints", async () => {
      const balanceBefore = await erc20.balanceOf(user1);
      await erc20.connect(user1Acc).mint(user1, 1);
      expect(await erc20.balanceOf(user1)).to.be.eq(balanceBefore.add(1));
    });

    describe("with a positive balance", async () => {
      beforeEach(async () => {
        await erc20.connect(user1Acc).mint(user1, 10);
      });

      it("returns the total supply", async () => {
        expect(await erc20.totalSupply()).to.be.equal(10);
      });

      it("burns", async () => {
        const balanceBefore = await erc20.balanceOf(user1);
        await erc20.connect(user1Acc).burn(user1, 1);
        expect(await erc20.balanceOf(user1)).to.be.eq(balanceBefore.sub(1));
      });

      it("transfers", async () => {
        const fromBalanceBefore = await erc20.balanceOf(user1);
        const toBalanceBefore = await erc20.balanceOf(user2);

        await erc20.connect(user1Acc).transfer(user2, 1);

        expect(await erc20.balanceOf(user1)).to.be.equal(
          fromBalanceBefore.sub(1)
        );
        expect(await erc20.balanceOf(user2)).to.be.equal(
          toBalanceBefore.add(1)
        );
      });

      it("transfers using transferFrom", async () => {
        const balanceBefore = await erc20.balanceOf(user2);
        await erc20.connect(user1Acc).transferFrom(user1, user2, 1);
        expect(await erc20.balanceOf(user2)).to.be.eq(balanceBefore.add(1));
      });

      it("should not transfer beyond balance", async () => {
        await expect(
          erc20.connect(user1Acc).transfer(user2, 100)
        ).to.be.revertedWith("ERC20: Insufficient balance");
        await expect(
          erc20.connect(user1Acc).transferFrom(user1, user2, 100)
        ).to.be.revertedWith("ERC20: Insufficient balance");
      });

      it("approves to increase allowance", async () => {
        const allowanceBefore = await erc20.allowance(user1, user2);
        await erc20.connect(user1Acc).approve(user2, 1);
        expect(await erc20.allowance(user1, user2)).to.be.eq(
          allowanceBefore.add(1)
        );
      });

      describe("with a positive allowance", async () => {
        beforeEach(async () => {
          await erc20.connect(user1Acc).approve(user2, 10);
        });

        it("transfers ether using transferFrom and allowance", async () => {
          const balanceBefore = await erc20.balanceOf(user2);
          await erc20.connect(user2Acc).transferFrom(user1, user2, 1);
          expect(await erc20.balanceOf(user2)).to.be.eq(balanceBefore.add(1));
        });

        it("should not transfer beyond allowance", async () => {
          await expect(
            erc20.connect(user2Acc).transferFrom(user1, user2, 20)
          ).to.be.revertedWith("ERC20: Insufficient approval");
        });
      });

      describe("with a maximum allowance", async () => {
        beforeEach(async () => {
          await erc20.connect(user1Acc).approve(user2, MAX);
        });

        it("does not decrease allowance using transferFrom", async () => {
          await erc20.connect(user2Acc).transferFrom(user1, user2, 1);
          expect(await erc20.allowance(user1, user2)).to.be.eq(MAX);
        });
      });
    });
  });
});
