import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import { id } from "../src/index";

import RestrictedERC20MockArtifact from "../artifacts/contracts/mocks/RestrictedERC20Mock.sol/RestrictedERC20Mock.json";
import EmergencyBrakeArtifact from "../artifacts/contracts/utils/EmergencyBrake.sol/EmergencyBrake.json";
import { RestrictedERC20Mock as ERC20 } from "../typechain/RestrictedERC20Mock";
import { EmergencyBrake } from "../typechain/EmergencyBrake";

import { BigNumber } from "ethers";

import { ethers, waffle } from "hardhat";
import { expect } from "chai";
const { deployContract, loadFixture } = waffle;

describe("EmergencyBrake", async function () {
  this.timeout(0);

  let plannerAcc: SignerWithAddress;
  let planner: string;
  let executorAcc: SignerWithAddress;
  let executor: string;
  let targetAcc: SignerWithAddress;
  let target: string;

  let contact1: ERC20;
  let contact2: ERC20;
  let brake: EmergencyBrake;

  const state = {
    UNPLANNED: 0,
    PLANNED: 1,
    EXECUTED: 2,
  };

  let MINT: string;
  let BURN: string;
  let APPROVE: string;
  let TRANSFER: string;
  const ROOT = "0x00000000";

  let permissions: { contact: string; signatures: string[] }[];

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    plannerAcc = signers[0];
    planner = plannerAcc.address;
    executorAcc = signers[1];
    executor = executorAcc.address;
    targetAcc = signers[2];
    target = targetAcc.address;

    contact1 = (await deployContract(plannerAcc, RestrictedERC20MockArtifact, [
      "Contact1",
      "CT1",
    ])) as ERC20;
    contact2 = (await deployContract(plannerAcc, RestrictedERC20MockArtifact, [
      "Contact2",
      "CT2",
    ])) as ERC20;
    brake = (await deployContract(plannerAcc, EmergencyBrakeArtifact, [
      planner,
      executor,
    ])) as EmergencyBrake;

    MINT = id(contact1.interface, "mint(address,uint256)");
    BURN = id(contact1.interface, "burn(address,uint256)");
    APPROVE = id(contact1.interface, "approve(address,uint256)");
    TRANSFER = id(contact1.interface, "transfer(address,uint256)");

    await contact1.grantRoles([MINT, BURN], target);
    await contact2.grantRoles([TRANSFER, APPROVE], target);

    await contact1.grantRole(ROOT, brake.address);
    await contact2.grantRole(ROOT, brake.address);

    permissions = [
      { contact: contact1.address, signatures: [MINT, BURN] },
      { contact: contact2.address, signatures: [TRANSFER, APPROVE] },
    ];
  });

  it("doesn't allow to cancel, execute, restore or terminate an unknown plan", async () => {
    const txHash =
      "0x18bba675edad0493c96b6415ff7457b8f2e9eee0a4a61bcca0b59a58b2abd4e5";
    await expect(brake.connect(plannerAcc).cancel(txHash)).to.be.revertedWith(
      "Emergency not planned for."
    );
    await expect(brake.connect(executorAcc).execute(txHash)).to.be.revertedWith(
      "Emergency not planned for."
    );
    await expect(brake.connect(plannerAcc).restore(txHash)).to.be.revertedWith(
      "Emergency plan not executed."
    );
    await expect(
      brake.connect(plannerAcc).terminate(txHash)
    ).to.be.revertedWith("Emergency plan not executed.");
  });

  it("only the planner can plan", async () => {
    await expect(
      brake.connect(executorAcc).plan(target, permissions)
    ).to.be.revertedWith("Access denied");
  });

  it("ROOT is out of bounds", async () => {
    const permissions = [
      { contact: contact1.address, signatures: [ROOT] },
      { contact: contact2.address, signatures: [TRANSFER, APPROVE] },
    ];
    await expect(
      brake.connect(plannerAcc).plan(target, permissions)
    ).to.be.revertedWith("Can't remove ROOT");
  });

  it("emergencies can be planned", async () => {
    const txHash = await brake
      .connect(plannerAcc)
      .callStatic.plan(target, permissions);

    expect(await brake.connect(plannerAcc).plan(target, permissions)).to.emit(
      brake,
      "Planned"
    );

    expect((await brake.plans(txHash)).state).to.equal(state.PLANNED);
  });

  describe("with a planned emergency", async () => {
    let txHash: string;

    beforeEach(async () => {
      txHash = await brake
        .connect(plannerAcc)
        .callStatic.plan(target, permissions);

      await brake.connect(plannerAcc).plan(target, permissions);
    });

    it("the same emergency plan cant't registered twice", async () => {
      await expect(
        brake.connect(plannerAcc).plan(target, permissions)
      ).to.be.revertedWith("Emergency already planned for.");
    });

    it("only the planner can cancel", async () => {
      await expect(
        brake.connect(executorAcc).cancel(txHash)
      ).to.be.revertedWith("Access denied");
    });

    it("cancels a plan", async () => {
      await expect(await brake.connect(plannerAcc).cancel(txHash)).to.emit(
        brake,
        "Cancelled"
      );
      //        .withArgs(txHash, target, contacts, signatures)
      expect((await brake.plans(txHash)).state).to.equal(state.UNPLANNED);
    });

    it("cant't restore or terminate a plan that hasn't been executed", async () => {
      await expect(
        brake.connect(plannerAcc).restore(txHash)
      ).to.be.revertedWith("Emergency plan not executed.");
      await expect(
        brake.connect(plannerAcc).terminate(txHash)
      ).to.be.revertedWith("Emergency plan not executed.");
    });

    it("only the executor can execute", async () => {
      await expect(
        brake.connect(plannerAcc).execute(txHash)
      ).to.be.revertedWith("Access denied");
    });

    it("can't revoke non-existing permissions", async () => {
      const permissions = [
        { contact: contact1.address, signatures: [MINT, BURN] },
        { contact: contact2.address, signatures: [MINT, BURN] },
      ];
      const txHash = await brake
        .connect(plannerAcc)
        .callStatic.plan(target, permissions); // GEt the txHash
      await brake.connect(plannerAcc).plan(target, permissions); // It can be planned, because permissions could be different at execution time
      await expect(
        brake.connect(executorAcc).execute(txHash)
      ).to.be.revertedWith("Permission not found");
    });

    it("plans can be executed", async () => {
      expect(await brake.connect(executorAcc).execute(txHash)).to.emit(
        brake,
        "Executed"
      );

      expect(await contact1.hasRole(MINT, target)).to.be.false;
      expect(await contact1.hasRole(BURN, target)).to.be.false;
      expect(await contact2.hasRole(APPROVE, target)).to.be.false;
      expect(await contact2.hasRole(TRANSFER, target)).to.be.false;

      expect((await brake.plans(txHash)).state).to.equal(state.EXECUTED);
    });

    describe("with an executed emergency plan", async () => {
      beforeEach(async () => {
        await brake.connect(executorAcc).execute(txHash);
      });

      it("the same emergency plan cant't executed twice", async () => {
        await expect(
          brake.connect(executorAcc).execute(txHash)
        ).to.be.revertedWith("Emergency not planned for.");
      });

      it("only the planner can restore or terminate", async () => {
        await expect(
          brake.connect(executorAcc).restore(txHash)
        ).to.be.revertedWith("Access denied");
        await expect(
          brake.connect(executorAcc).terminate(txHash)
        ).to.be.revertedWith("Access denied");
      });

      it("state can be restored", async () => {
        expect(await brake.connect(plannerAcc).restore(txHash)).to.emit(
          brake,
          "Restored"
        );

        expect(await contact1.hasRole(MINT, target)).to.be.true;
        expect(await contact1.hasRole(BURN, target)).to.be.true;
        expect(await contact2.hasRole(APPROVE, target)).to.be.true;
        expect(await contact2.hasRole(TRANSFER, target)).to.be.true;

        expect((await brake.plans(txHash)).state).to.equal(state.PLANNED);
      });

      it("target can be terminated", async () => {
        expect(await brake.connect(plannerAcc).terminate(txHash)).to.emit(
          brake,
          "Terminated"
        );

        expect((await brake.plans(txHash)).state).to.equal(state.UNPLANNED);
      });
    });
  });
});
