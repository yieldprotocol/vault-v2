// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/crab/CrabOracle.sol";
import {ICrabStrategy} from "../../oracles/crab/CrabOracle.sol";
import "../../oracles/uniswap/UniswapV3Oracle.sol";

contract CrabOracleTest is Test {
    CrabOracle public crabOracle;
    bytes6 baseId = 0x323900000000;
    bytes6 quoteId = 0x303100000000;
    UniswapV3Oracle uniswapV3Oracle =
        UniswapV3Oracle(0x358538ea4F52Ac15C551f88C701696f6d9b38F3C);

    function setUp() public {
        crabOracle = new CrabOracle(
            ICrabStrategy(0x3B960E47784150F5a63777201ee2B15253D713e8)
        );
        vm.startPrank(0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        uniswapV3Oracle.grantRole(0xe4650418, 0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        
        uniswapV3Oracle.setSource(
            crabOracle.weth(),
            crabOracle.oSQTH(),
            0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C,
            100
        );
        vm.stopPrank();
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