import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import { id } from "../src/index";

import ERC20MockArtifact from "../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json";
import TimelockArtifact from "../artifacts/contracts/utils/Timelock.sol/Timelock.json";
import { ERC20Mock as ERC20 } from "../typechain/ERC20Mock";
import { Timelock } from "../typechain/Timelock";

import { BigNumber } from "ethers";

import { ethers, waffle } from "hardhat";
import { expect } from "chai";
const { deployContract, loadFixture } = waffle;

describe("Timelock", async function () {
  const STATE = {
    UNKNOWN: 0,
    PROPOSED: 1,
    APPROVED: 2,
  };

  let governorAcc: SignerWithAddress;
  let governor: string;
  let executorAcc: SignerWithAddress;
  let executor: string;
  let otherAcc: SignerWithAddress;
  let other: string;

  let target1: ERC20;
  let target2: ERC20;
  let timelock: Timelock;

  let timestamp: number;
  let resetChain: number;
  let now: BigNumber;

  before(async () => {
    resetChain = await ethers.provider.send("evm_snapshot", []);
    const signers = await ethers.getSigners();
    governorAcc = signers[0];
    governor = governorAcc.address;
    executorAcc = signers[1];
    executor = executorAcc.address;
    otherAcc = signers[2];
    other = otherAcc.address;
  });

  after(async () => {
    await ethers.provider.send("evm_revert", [resetChain]);
  });

  beforeEach(async () => {
    target1 = (await deployContract(governorAcc, ERC20MockArtifact, [
      "Target1",
      "TG1",
    ])) as ERC20;
    target2 = (await deployContract(governorAcc, ERC20MockArtifact, [
      "Target2",
      "TG2",
    ])) as ERC20;
    timelock = (await deployContract(governorAcc, TimelockArtifact, [
      governor,
      executor,
    ])) as Timelock;
    ({ timestamp } = await ethers.provider.getBlock("latest"));
    now = BigNumber.from(timestamp);

    const setDelayCall = [
      {
        target: timelock.address,
        data: timelock.interface.encodeFunctionData("setDelay", [
          2 * 24 * 60 * 60,
        ]),
      },
    ];

    const txHash = await timelock.callStatic.propose(setDelayCall);
    await timelock.propose(setDelayCall);
    await timelock.approve(txHash);
    await timelock.execute(setDelayCall);
  });

  it("doesn't allow governance changes to governor", async () => {
    await expect(timelock.setDelay(0)).to.be.revertedWith("Access denied");
    await expect(timelock.grantRole("0x00000000", governor)).to.be.revertedWith(
      "Only admin"
    );
    await expect(
      timelock.grantRole(id(timelock.interface, "setDelay(uint32)"), governor)
    ).to.be.revertedWith("Only admin");
    await expect(
      timelock.revokeRole(id(timelock.interface, "setDelay(uint32)"), governor)
    ).to.be.revertedWith("Only admin");
  });

  it("only the governor can propose", async () => {
    const functionCalls = [
      {
        target: target1.address,
        data: target1.interface.encodeFunctionData("mint", [governor, 1]),
      },
    ];
    await expect(
      timelock.connect(otherAcc).propose(functionCalls)
    ).to.be.revertedWith("Access denied");
  });

  it("proposes a transaction", async () => {
    const functionCalls = [
      {
        target: target1.address,
        data: target1.interface.encodeFunctionData("mint", [governor, 1]),
      },
    ];
    const txHash = await timelock.callStatic.propose(functionCalls);

    await expect(await timelock.propose(functionCalls)).to.emit(
      timelock,
      "Proposed"
    );
    //      .withArgs(txHash, targets, data, eta)
    const proposal = await timelock.proposals(txHash);
    expect(proposal.state).to.equal(STATE.PROPOSED);
  });

  describe("with a proposed transaction", async () => {
    let functionCalls: { target: string; data: string }[];
    let txHash: string;

    beforeEach(async () => {
      functionCalls = [
        {
          target: target1.address,
          data: target1.interface.encodeFunctionData("mint", [governor, 1]),
        },
        {
          target: target2.address,
          data: target1.interface.encodeFunctionData("approve", [governor, 1]),
        },
      ];
      txHash = await timelock.callStatic.propose(functionCalls);
      await timelock.propose(functionCalls);
    });

    it("doesn't allow to propose the same transaction twice", async () => {
      await expect(timelock.propose(functionCalls)).to.be.revertedWith(
        "Already proposed."
      );
    });

    it("allows proposing repeated transactions", async () => {
      const txHash2 = await timelock.callStatic.proposeRepeated(
        functionCalls,
        1
      );

      await expect(await timelock.proposeRepeated(functionCalls, 1)).to.emit(
        timelock,
        "Proposed"
      );
      //      .withArgs(txHash, targets, data, eta)
      const proposal = await timelock.proposals(txHash2);
      expect(proposal.state).to.equal(STATE.PROPOSED);
    });

    it("only the governor can approve", async () => {
      await expect(
        timelock.connect(otherAcc).approve(txHash)
      ).to.be.revertedWith("Access denied");
    });

    it("doesn't allow to approve if not proposed", async () => {
      const txHash =
        "0x00004732e64f236e5182740fa5473c496f60cecc294538c44897d62be999d1ed";
      await expect(timelock.approve(txHash)).to.be.revertedWith(
        "Not proposed."
      );
    });

    it("approves a transaction", async () => {
      await expect(await timelock.approve(txHash)).to.emit(
        timelock,
        "Approved"
      );
      //        .withArgs(txHash, targets, data, eta)
      expect(await timelock.proposals(txHash)).not.equal(0);
    });

    describe("with an approved transaction", async () => {
      let snapshotId: string;
      let timestamp: number;
      let now: BigNumber;
      let eta: BigNumber;
      let txHash2: string;
      let txHash3: string;

      beforeEach(async () => {
        ({ timestamp } = await ethers.provider.getBlock("latest"));
        now = BigNumber.from(timestamp);
        eta = now.add(await timelock.delay()).add(100);
        await timelock.approve(txHash);

        txHash2 = await timelock.callStatic.proposeRepeated(functionCalls, 1);
        await timelock.proposeRepeated(functionCalls, 1);
        await timelock.approve(txHash2);

        txHash3 = await timelock.callStatic.proposeRepeated(functionCalls, 2);
        await timelock.proposeRepeated(functionCalls, 2);
      });

      it("only the governor can execute", async () => {
        await expect(
          timelock.connect(otherAcc).execute(functionCalls)
        ).to.be.revertedWith("Access denied");
      });

      it("doesn't allow to execute before eta", async () => {
        await expect(timelock.execute(functionCalls)).to.be.revertedWith(
          "ETA not reached"
        );
      });

      it("doesn't allow to execute if not approved", async () => {
        const functionCalls = [
          {
            target: target1.address,
            data: target1.interface.encodeFunctionData("mint", [governor, 1]),
          },
        ];
        await expect(timelock.execute(functionCalls)).to.be.revertedWith(
          "Not approved."
        );
      });

      it("doesn't allow to execute after grace period", async () => {
        const eta = now.add(await timelock.delay()).add(100);

        const snapshotId = await ethers.provider.send("evm_snapshot", []);
        await ethers.provider.send("evm_mine", [
          eta
            .add(await timelock.GRACE_PERIOD())
            .add(100)
            .toNumber(),
        ]);

        await expect(timelock.execute(functionCalls)).to.be.revertedWith(
          "Proposal is stale"
        );

        await ethers.provider.send("evm_revert", [snapshotId]);
      });

      it("doesn't allow to execute to a non-contract", async () => {
        const functionCalls = [
          {
            target: governor,
            data: target1.interface.encodeFunctionData("mint", [governor, 1]),
          },
        ];

        const tmpTxHash = await timelock.callStatic.propose(functionCalls);
        await timelock.propose(functionCalls);
        await timelock.approve(tmpTxHash);

        const snapshotId = await ethers.provider.send("evm_snapshot", []);
        await ethers.provider.send("evm_mine", [eta.add(100).toNumber()]);

        await expect(timelock.execute(functionCalls)).to.be.revertedWith(
          "Call to a non-contract"
        );

        await ethers.provider.send("evm_revert", [snapshotId]);
      });

      describe("once the eta arrives", async () => {
        beforeEach(async () => {
          snapshotId = await ethers.provider.send("evm_snapshot", []);
          await ethers.provider.send("evm_mine", [eta.toNumber()]);
        });

        afterEach(async () => {
          await ethers.provider.send("evm_revert", [snapshotId]);
        });

        it("executes a transaction", async () => {
          await expect(await timelock.execute(functionCalls))
            .to.emit(timelock, "Executed")
            //          .withArgs(txHash, targets, data, eta)
            .to.emit(target1, "Transfer")
            //          .withArgs(null, governor, 1)
            .to.emit(target2, "Approval");
          //          .withArgs(governor, governor, 1)
          expect((await timelock.proposals(txHash)).state).to.equal(
            STATE.UNKNOWN
          );
          expect(await target1.balanceOf(governor)).to.equal(1);
          expect(await target2.allowance(timelock.address, governor)).to.equal(
            1
          );
        });

        it("executes a repeated transaction", async () => {
          await expect(await timelock.executeRepeated(functionCalls, 1))
            .to.emit(timelock, "Executed")
            //          .withArgs(txHash, targets, data, eta)
            .to.emit(target1, "Transfer")
            //          .withArgs(null, governor, 1)
            .to.emit(target2, "Approval");
          //          .withArgs(governor, governor, 1)
          expect((await timelock.proposals(txHash2)).state).to.equal(
            STATE.UNKNOWN
          );
          expect(await target1.balanceOf(governor)).to.equal(1);
          expect(await target2.allowance(timelock.address, governor)).to.equal(
            1
          );
        });
      });
    });
  });
});
