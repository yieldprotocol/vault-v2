// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "../../oracles/accumulator/AccumulatorMultiOracle.sol";
import "../utils/TestConstants.sol";

abstract contract ZeroState is Test, TestConstants {
    AccumulatorMultiOracle public accumulator;

    address timelock;
    address underlying;
    bytes6 public baseOne = 0x6d1caec02cbf;
    bytes6 public baseTwo = 0x8a4fee8b848e;

    modifier onlyMock() {
        if (!vm.envOr(MOCK, true)) return;
        _;
    }

    function setUpMock() public {
        accumulator = new AccumulatorMultiOracle();
        accumulator.grantRole(accumulator.setSource.selector, address(this));
        accumulator.grantRole(accumulator.updatePerSecondRate.selector, address(this));

        baseOne = 0x6d1caec02cbf;
        baseTwo = 0x8a4fee8b848e;
    }

    function setUpHarness(string memory network) public {
        timelock = addresses[network][TIMELOCK];

        accumulator = AccumulatorMultiOracle(vm.envAddress("ORACLE"));
        baseOne = bytes6(vm.envBytes32("BASE"));
        underlying = vm.envAddress("ADDRESS");

        vm.startPrank(timelock);
        accumulator.grantRole(accumulator.setSource.selector, address(this));
        accumulator.grantRole(accumulator.updatePerSecondRate.selector, address(this));
        vm.stopPrank();
    }

    function setUp() public virtual {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);
        string memory network = vm.envOr(NETWORK, LOCALHOST);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);
    }
}

abstract contract WithSourceSet is ZeroState {
    function setUp() public override {
        super.setUp();
        if(vm.envOr(MOCK, true)){
             accumulator.setSource(baseOne, RATE, WAD, WAD);
        }
    }
}

contract AccumulatorOracleTest is ZeroState {
    function testSetSourceOnlyOnce() public onlyMock {
        accumulator.setSource(baseOne, RATE, WAD, WAD);
        vm.expectRevert("Source is already set");
        accumulator.setSource(baseOne, RATE, WAD, WAD);
    }

    function testCannotCallUninitializedSource() public onlyMock {
        vm.expectRevert("Source not found");
        accumulator.updatePerSecondRate(baseOne, RATE, WAD);
    }

    function testCannotCallStaleAccumulator() public onlyMock {
        accumulator.setSource(baseOne, RATE, WAD, WAD);
        skip(100);
        vm.expectRevert("stale accumulator");
        accumulator.updatePerSecondRate(baseOne, RATE, WAD);
    }

    function testRevertOnSourceUnknown() public onlyMock {
        accumulator.setSource(baseOne, RATE, WAD, WAD);
        vm.expectRevert("Source not found");
        accumulator.peek(bytes32(baseTwo), RATE, WAD);
        vm.expectRevert("Source not found");
        accumulator.peek(bytes32(baseOne), CHI, WAD);
    }

    function testDoesNotMixUpSources() public onlyMock {
        accumulator.setSource(baseOne, RATE, WAD, WAD);
        accumulator.setSource(baseOne, CHI, WAD * 2, WAD);
        accumulator.setSource(baseTwo, RATE, WAD * 3, WAD);
        accumulator.setSource(baseTwo, CHI, WAD * 4, WAD);

        uint256 amount;
        (amount,) = accumulator.peek(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        (amount,) = accumulator.peek(bytes32(baseOne), CHI, WAD);
        assertEq(amount, WAD * 2, "Conversion unsuccessful");
        (amount,) = accumulator.peek(bytes32(baseTwo), RATE, WAD);
        assertEq(amount, WAD * 3, "Conversion unsuccessful");
        (amount,) = accumulator.peek(bytes32(baseTwo), CHI, WAD);
        assertEq(amount, WAD * 4, "Conversion unsuccessful");
    }
}

contract WithSourceSetTest is WithSourceSet {
    function testComputesWithoutCheckpoints() public {
        uint256 amount;
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(10);
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(2);
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
    }

    function testComputesWithCheckpointing() public {
        uint256 amount;
        vm.roll(block.number + 1);
        skip(1);
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        skip(10);
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
    }

    function testUpdatesPeek() public {
        uint256 amount;
        skip(10);
        (amount,) = accumulator.peek(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        accumulator.get(bytes32(baseOne), RATE, WAD);
        (amount,) = accumulator.peek(bytes32(baseOne), RATE, WAD);
    }
}