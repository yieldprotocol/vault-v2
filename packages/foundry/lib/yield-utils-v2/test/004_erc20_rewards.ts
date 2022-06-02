import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import { constants, id } from "../src/index";
const { WAD } = constants;

import ERC20MockArtifact from "../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json";
import ERC20RewardsMockArtifact from "../artifacts/contracts/mocks/ERC20RewardsMock.sol/ERC20RewardsMock.json";
import { ERC20Mock as ERC20 } from "../typechain/ERC20Mock";
import { ERC20RewardsMock as ERC20Rewards } from "../typechain/ERC20RewardsMock";

import { BigNumber } from "ethers";

import { ethers, waffle } from "hardhat";
import { expect } from "chai";
const { deployContract, loadFixture } = waffle;

function almostEqual(x: BigNumber, y: BigNumber, p: BigNumber) {
  // Check that abs(x - y) < p:
  const diff = x.gt(y) ? BigNumber.from(x).sub(y) : BigNumber.from(y).sub(x); // Not sure why I have to convert x and y to BigNumber
  expect(diff.div(p)).to.eq(0); // Hack to avoid silly conversions. BigNumber truncates decimals off.
}

describe("ERC20Rewards", async function () {
  this.timeout(0);

  let ownerAcc: SignerWithAddress;
  let owner: string;
  let user1: string;
  let user1Acc: SignerWithAddress;
  let user2: string;
  let user2Acc: SignerWithAddress;

  let governance: ERC20;
  let rewards: ERC20Rewards;

  const ZERO_ADDRESS = "0x" + "0".repeat(40);

  async function fixture() {} // For now we just use this to snapshot and revert the state of the blockchain

  before(async () => {
    await loadFixture(fixture); // This snapshots the blockchain as a side effect
    const signers = await ethers.getSigners();
    ownerAcc = signers[0];
    owner = ownerAcc.address;
    user1Acc = signers[1];
    user1 = user1Acc.address;
    user2Acc = signers[2];
    user2 = user2Acc.address;
  });

  after(async () => {
    await loadFixture(fixture); // We advance the time to test maturity features, this rolls it back after the tests
  });

  beforeEach(async () => {
    governance = (await deployContract(ownerAcc, ERC20MockArtifact, [
      "Governance Token",
      "GOV",
    ])) as ERC20;
    rewards = (await deployContract(ownerAcc, ERC20RewardsMockArtifact, [
      "Token with rewards",
      "REW",
      18,
    ])) as ERC20Rewards;

    await rewards.grantRoles(
      [
        id(rewards.interface, "setRewardsToken(address)"),
        id(rewards.interface, "setRewards(uint32,uint32,uint96)"),
      ],
      owner
    );
  });

  it("mints, transfers, burns", async () => {
    expect(await rewards.mint(user1, 1))
      .to.emit(rewards, "Transfer")
      .withArgs(ZERO_ADDRESS, user1, 1);

    expect(await rewards.connect(user1Acc).transfer(user2, 1))
      .to.emit(rewards, "Transfer")
      .withArgs(user1, user2, 1);

    expect(await rewards.connect(user2Acc).burn(user2, 1))
      .to.emit(rewards, "Transfer")
      .withArgs(user2, ZERO_ADDRESS, 1);
  });

  it("doesn't set a period where end < start", async () => {
    await expect(rewards.setRewards(2, 1, 3)).to.be.revertedWith(
      "Incorrect input"
    );
  });

  it("sets a rewards token and program", async () => {
    await expect(rewards.setRewards(1, 2, 3)).to.be.revertedWith(
      "Rewards token not set"
    );

    await expect(rewards.setRewardsToken(governance.address))
      .to.emit(rewards, "RewardsTokenSet")
      .withArgs(governance.address);

    await expect(rewards.setRewardsToken(rewards.address)).to.be.revertedWith(
      "Rewards token already set"
    );

    await expect(rewards.setRewards(1, 2, 3))
      .to.emit(rewards, "RewardsSet")
      .withArgs(1, 2, 3);

    const rewardsPeriod = await rewards.rewardsPeriod();
    expect(rewardsPeriod.start).to.equal(1);
    expect(rewardsPeriod.end).to.equal(2);
    expect((await rewards.rewardsPerToken()).rate).to.equal(3);
  });

  describe("with a rewards program", async () => {
    let snapshotId: string;
    let timestamp: number;
    let start: number;
    let length: number;
    let mid: number;
    let end: number;
    let rate: BigNumber;

    before(async () => {
      ({ timestamp } = await ethers.provider.getBlock("latest"));
      start = timestamp + 1000000;
      length = 2000000;
      mid = start + length / 2;
      end = start + length;
      rate = WAD.div(length);
    });

    beforeEach(async () => {
      await rewards.setRewardsToken(governance.address);
      await rewards.setRewards(start, end, rate);
      await governance.mint(rewards.address, WAD);
      await rewards.mint(user1, WAD); // So that total supply is not zero
    });

    describe("before the program", async () => {
      it("allows to change the program", async () => {
        expect(await rewards.setRewards(4, 5, 6))
          .to.emit(rewards, "RewardsSet")
          .withArgs(4, 5, 6);
      });

      it("doesn't update rewards per token", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.mint(user1, WAD);
        expect((await rewards.rewardsPerToken()).accumulated).to.equal(0);
      });

      it("doesn't update user rewards", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.mint(user1, WAD);
        expect((await rewards.rewards(user1)).accumulated).to.equal(0);
      });
    });

    describe("during the program", async () => {
      beforeEach(async () => {
        snapshotId = await ethers.provider.send("evm_snapshot", []);
        await ethers.provider.send("evm_mine", [mid]);
      });

      afterEach(async () => {
        await ethers.provider.send("evm_revert", [snapshotId]);
      });

      it("doesn't allow to change the program", async () => {
        await expect(rewards.setRewards(4, 5, 6)).to.be.revertedWith(
          "Ongoing rewards"
        );
      });

      it("updates rewards per token on mint", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.mint(user1, WAD);
        almostEqual(
          (await rewards.rewardsPerToken()).accumulated,
          BigNumber.from(timestamp - start).mul(rate), //  ... * 1e18 / totalSupply = ... * WAD / WAD
          BigNumber.from(timestamp - start)
            .mul(rate)
            .div(100000)
        );
      });

      it("updates user rewards on mint", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.mint(user1, WAD);
        const rewardsPerToken = (await rewards.rewardsPerToken()).accumulated;
        almostEqual(
          (await rewards.rewards(user1)).accumulated,
          rewardsPerToken, //  (... - paidRewardPerToken[user]) * userBalance / 1e18 = (... - 0) * WAD / WAD
          rewardsPerToken.div(100000)
        );
      });

      it("updates rewards per token on burn", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.burn(user1, WAD);
        almostEqual(
          (await rewards.rewardsPerToken()).accumulated,
          BigNumber.from(timestamp - start).mul(rate), //  ... * 1e18 / totalSupply = ... * WAD / WAD
          BigNumber.from(timestamp - start)
            .mul(rate)
            .div(100000)
        );
      });

      it("updates user rewards on burn", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.burn(user1, WAD);
        const rewardsPerToken = (await rewards.rewardsPerToken()).accumulated;
        almostEqual(
          (await rewards.rewards(user1)).accumulated,
          rewardsPerToken, //  (... - paidRewardPerToken[user]) * userBalance / 1e18 = (... - 0) * WAD / WAD
          rewardsPerToken.div(100000)
        );
      });

      it("updates user rewards on transfer", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.connect(user1Acc).transfer(user2, WAD);
        const rewardsPerToken = (await rewards.rewardsPerToken()).accumulated;
        almostEqual(
          (await rewards.rewards(user1)).accumulated,
          rewardsPerToken, //  (... - paidRewardPerToken[user]) * userBalance / 1e18 = (... - 0) * WAD / WAD
          rewardsPerToken.div(100000)
        );
        expect((await rewards.rewards(user2)).accumulated).to.equal(0);
        expect(await rewards.connect(user2Acc).claim(user2)) // No time has passed, so user2 doesn't get to claim anything
          .to.emit(rewards, "Claimed")
          .withArgs(user2, 0);
      });

      it("allows to claim", async () => {
        expect(await rewards.connect(user1Acc).claim(user1))
          .to.emit(rewards, "Claimed")
          .withArgs(user1, await governance.balanceOf(user1));

        expect(await governance.balanceOf(user1)).to.equal(
          (await rewards.rewardsPerToken()).accumulated
        ); // See previous test
        expect((await rewards.rewards(user1)).accumulated).to.equal(0);
        expect((await rewards.rewards(user1)).checkpoint).to.equal(
          (await rewards.rewardsPerToken()).accumulated
        );
      });
    });

    describe("after the program", async () => {
      beforeEach(async () => {
        snapshotId = await ethers.provider.send("evm_snapshot", []);
        await ethers.provider.send("evm_mine", [end + 1000000]);
      });

      afterEach(async () => {
        await ethers.provider.send("evm_revert", [snapshotId]);
      });

      it("allows to change the program", async () => {
        expect(await rewards.setRewards(4, 5, 6))
          .to.emit(rewards, "RewardsSet")
          .withArgs(4, 5, 6);
      });

      it("doesn't update rewards per token past the end date", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.mint(user1, WAD);
        expect((await rewards.rewardsPerToken()).accumulated).to.equal(
          BigNumber.from(length).mul(rate)
        ); // Total supply has been WAD for the whole program, but rewardsPerToken is scaled 1e18 up
      });

      it("doesn't update user rewards", async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        await rewards.mint(user1, WAD);
        expect((await rewards.rewards(user1)).accumulated).to.equal(
          BigNumber.from(length).mul(rate)
        ); // The guy got all the rewards == length * rate
      });
    });
  });
});
