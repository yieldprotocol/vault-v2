// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "../../oracles/accumulator/AccumulatorMultiOracle.sol";
import "../utils/TestConstants.sol";

abstract contract ZeroState is Test, TestConstants {
    AccumulatorMultiOracle public accumulator;

    bytes6 public baseOne = 0x6d1caec02cbf;
    bytes6 public baseTwo = 0x8a4fee8b848e;

    function setUp() public virtual {
        accumulator = new AccumulatorMultiOracle();
        accumulator.grantRole(accumulator.setSource.selector, address(this));
        accumulator.grantRole(accumulator.updatePerSecondRate.selector, address(this));
    }
}

abstract contract WithSourceSet is ZeroState {
    function setUp() public override {
        super.setUp();
        accumulator.setSource(baseOne, RATE, WAD, WAD * 2);
    }
}

contract WithSourceSetTest is WithSourceSet {
    function testComputesWithoutCheckpoints() public {
        uint256 amount;
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(10);
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD * 1024, "Conversion unsuccessful");
        skip(2);
        (amount,) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD * 4096, "Conversion unsuccessful");
    }

    function testComputesWithCheckpointing() public {

    }

    function testUpdatesPeek() public {

    }
}