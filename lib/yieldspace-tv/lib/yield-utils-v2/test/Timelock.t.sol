// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/utils/Timelock.sol";
import { ERC20Mock } from "../src/mocks/ERC20Mock.sol";
import { TestExtensions } from "./utils/TestExtensions.sol";
import { TestConstants } from "./utils/TestConstants.sol";


using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions, TestConstants {

    event DelaySet(uint256 indexed delay);
    event Proposed(bytes32 indexed txHash);
    event Approved(bytes32 indexed txHash, uint32 eta);
    event Cancelled(bytes32 indexed txHash);
    event Executed(bytes32 indexed txHash);

    ERC20Mock public target;
    ERC20Mock public otherTarget;
    Timelock public timelock;
    address governor;
    address executor;
    address other;

    ITimelock.Call[] proposal;
    bytes32 proposalHash;
    ITimelock.Call[] proposalNonContract;
    ITimelock.Call[] proposalWithValue;
    ITimelock.Call[] proposalSetDelay;

    function setUpMock() public {
        governor = address(1);
        executor = address(2);
        timelock = new Timelock(governor, executor);
        target = new ERC20Mock("Test", "TST");
        otherTarget = new ERC20Mock("Other", "OTH");
    }

    function setUpHarness(string memory network) public {
        setUpMock(); // TODO: Think about a test harness.
    }

    function setUp() public virtual {
        string memory network = vm.envString(NETWORK);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envBool(MOCK)) setUpMock();
        else setUpHarness(network);

        //... Users ...
        other = address(3);
        vm.label(governor, "governor");
        vm.label(executor, "executor");
        vm.label(other, "other");
        vm.label(address(timelock), "timelock");

        proposal.push(ITimelock.Call({
            target: address(target),
            data: abi.encodeWithSelector(ERC20Mock.mint.selector, other, 1)
        }));
        proposal.push(ITimelock.Call({
            target: address(otherTarget),
            data: abi.encodeWithSelector(ERC20Mock.mint.selector, other, 1)
        }));
        proposalHash = keccak256(abi.encode(proposal));

        proposalNonContract.push(ITimelock.Call({
            target: address(0),
            data: abi.encodeWithSelector(ERC20Mock.mint.selector, other, 1)
        }));

        ITimelock.Call memory innerCall = ITimelock.Call({
            target: other,
            data: ""
        });
        proposalWithValue.push(ITimelock.Call({
            target: address(timelock),
            data: abi.encodeWithSelector(Timelock.callWithValue.selector, innerCall, 1)
        }));

        // We will use this proposal to test the setDaly functionality
        proposalSetDelay.push(ITimelock.Call({
            target: address(timelock),
            data: abi.encodeWithSelector(Timelock.setDelay.selector, 2 days)
        }));

        // Set the delay bypassing the timelock proposal process
        stdstore
            .target(address(timelock))
            .sig("delay()")
            .checked_write(10000);
    }
}

contract DeployedTest is Deployed {
        function testAuth() public {
        
        vm.startPrank(executor);
        vm.expectRevert("Access denied");
        timelock.setDelay(0);

        vm.expectRevert("Access denied");
        timelock.approve(bytes32(0));

        vm.expectRevert("Access denied");
        timelock.cancel(bytes32(0));

        vm.expectRevert("Only admin");
        timelock.grantRole(Timelock.setDelay.selector, other);
        vm.stopPrank();
    }

    function testOnlyApproveIfProposed() public {
        vm.expectRevert("Not proposed.");
        vm.prank(governor);
        timelock.approve(bytes32(0));
    }

    function testOnlyCancelIfProposed() public {
        vm.expectRevert("Not found.");
        vm.prank(governor);
        timelock.cancel(bytes32(0));
    }

    function testPropose() public {
        vm.expectEmit(true, false, false, false);
        emit Proposed(proposalHash);
        vm.prank(governor);
        timelock.propose(proposal);

        (Timelock.STATE state, uint32 eta) = timelock.proposals(proposalHash);
        assertEq(uint16(state), uint16(Timelock.STATE.PROPOSED));
        assertEq(eta, 0);
    }
}

abstract contract ProposedState is Deployed {
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(governor);
        timelock.propose(proposal);
        timelock.propose(proposalNonContract);
        timelock.propose(proposalWithValue);
        timelock.propose(proposalSetDelay);
        vm.stopPrank();
    }
}

contract ProposedTest is ProposedState {
    function testProposeAgain() public {
        vm.expectRevert("Already proposed.");
        vm.prank(governor);
        timelock.propose(proposal);
    }

    function testApprove() public {
        uint32 expectedEta = uint32(block.timestamp + timelock.delay());
        vm.expectEmit(false, true, false, false);
        emit Approved(proposalHash, expectedEta);
        vm.prank(governor);
        timelock.approve(proposalHash);

        (Timelock.STATE state, uint32 eta) = timelock.proposals(proposalHash);
        assertEq(uint16(state), uint16(Timelock.STATE.APPROVED));
        assertEq(eta, expectedEta);
    }

    function testCancel() public {
        vm.expectEmit(false, false, true, false);
        emit Cancelled(proposalHash);
        vm.prank(governor);
        timelock.cancel(proposalHash);

        (Timelock.STATE state, uint32 eta) = timelock.proposals(proposalHash);
        assertEq(uint16(state), uint16(Timelock.STATE.UNKNOWN));
        assertEq(eta, 0);
    }

    function testExecuteNotApproved() public {
        vm.expectRevert("Not approved.");
        vm.prank(executor);
        timelock.execute(proposal);
    }
}

abstract contract ApprovedState is ProposedState {
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(governor);
        timelock.approve(proposalHash);
        timelock.approve(keccak256(abi.encode(proposalNonContract)));
        timelock.approve(keccak256(abi.encode(proposalWithValue)));
        timelock.approve(keccak256(abi.encode(proposalSetDelay)));
        vm.stopPrank();
    }
}

contract ApprovedTest is ApprovedState {
    function testApproveAgain() public {
        vm.expectRevert("Not proposed.");
        vm.prank(governor);
        timelock.approve(proposalHash);
    }

    function testCancel() public {
        vm.expectEmit(false, false, true, false);
        emit Cancelled(proposalHash);
        vm.prank(governor);
        timelock.cancel(proposalHash);

        (Timelock.STATE state, uint32 eta) = timelock.proposals(proposalHash);
        assertEq(uint16(state), uint16(Timelock.STATE.UNKNOWN));
        assertEq(eta, 0);
    }

    function testExecuteBeforeETA() public {
        vm.expectRevert("ETA not reached.");
        vm.prank(executor);
        timelock.execute(proposal);
    }
}
abstract contract afterETA is ApprovedState {
    function setUp() public virtual override {
        super.setUp();
        (, uint32 eta) = timelock.proposals(proposalHash);
        vm.warp(eta + 1);
    }
}

contract AfterETATest is afterETA {
    function testExecute() public {
        vm.expectEmit(true, false, false, true);
        emit Executed(proposalHash);
        vm.prank(executor);
        timelock.execute(proposal);

        (Timelock.STATE state, uint32 eta) = timelock.proposals(proposalHash);
        assertEq(uint16(state), uint16(Timelock.STATE.UNKNOWN));
        assertEq(eta, 0);

        // Check that the proposal was executed
        assertEq(ERC20Mock(address(target)).balanceOf(other), 1);
        assertEq(ERC20Mock(address(otherTarget)).balanceOf(other), 1);
    }

    function testRevertExecuteToNonContract() public {
        vm.expectRevert("Call to a non-contract");
        vm.prank(executor);
        timelock.execute(proposalNonContract);
    }

    function testExecuteWithValue() public {
        uint256 otherBalance = address(other).balance;
        vm.deal(address(timelock), 1);
        vm.prank(executor);
        timelock.execute(proposalWithValue);

        // Check that the proposal was executed
        assertEq(address(other).balance, otherBalance + 1);
    }

    function testExecuteSetDelay() public {
        vm.prank(executor);
        timelock.execute(proposalSetDelay);

        // Check that the proposal was executed
        assertEq(timelock.delay(), 2 days);
    }
}
