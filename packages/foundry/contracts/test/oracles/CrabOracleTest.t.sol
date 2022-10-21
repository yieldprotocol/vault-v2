// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/crab/CrabOracle.sol";
import {ICrabStrategy} from "../../oracles/crab/CrabOracle.sol";

contract CrabOracleTest is Test {
    CrabOracle public crabOracle;
    bytes6 baseId = 0x303000000000;
    bytes6 quoteId = 0x303100000000;

    function setUp() public {
        crabOracle = new CrabOracle(
            ICrabStrategy(0x3B960E47784150F5a63777201ee2B15253D713e8)
        );
    }

    function testPeek() public {
        (uint256 amount, ) = crabOracle.peek(
            bytes32(baseId),
            bytes32(quoteId),
            1e18
        );
        assertEq(amount, 1000000000000000000);
    }

    function testPeekReversed() public {
        (uint256 amount, ) = crabOracle.peek(
            bytes32(quoteId),
            bytes32(baseId),
            1e18
        );
        assertEq(amount, 1000000000000000000);
    }
}
