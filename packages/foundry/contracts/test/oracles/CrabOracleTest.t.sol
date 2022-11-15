// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/crab/CrabOracle.sol";
import {ICrabStrategy} from "../../oracles/crab/CrabOracle.sol";
import "../../oracles/uniswap/UniswapV3Oracle.sol";
import "../utils/TestConstants.sol";

contract CrabOracleTest is Test, TestConstants {
    CrabOracle public crabOracle;
    bytes6 baseId = 0x323900000000;
    bytes6 quoteId = ETH;
    UniswapV3Oracle uniswapV3Oracle =
        UniswapV3Oracle(0x358538ea4F52Ac15C551f88C701696f6d9b38F3C);
    address uniswapV3oSQTHPool = 0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C;
    address crabStrategyV2 = 0x3B960E47784150F5a63777201ee2B15253D713e8;
    address timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;

    function setUp() public {
        vm.createSelectFork("mainnet", 15974678);
        crabOracle = new CrabOracle();
        crabOracle.grantRole(0xac426579, address(this));
        crabOracle.setSource(
            baseId,
            0x313900000000,
            ICrabStrategy(crabStrategyV2),
            IOracle(address(uniswapV3Oracle))
        );

        vm.startPrank(timelock);
        uniswapV3Oracle.grantRole(0xe4650418, timelock);
        uniswapV3Oracle.setSource(
            crabOracle.weth(),
            crabOracle.oSQTH(),
            uniswapV3oSQTHPool,
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
        emit log_named_uint("Crab in ETH Value", amount);
        assertEq(amount, 962695640155633739);
    }

    function testPeekReversed() public {
        (uint256 amount, ) = crabOracle.peek(
            bytes32(quoteId),
            bytes32(baseId),
            1e18
        );
        emit log_named_uint("ETH in Crab Value", amount);
        assertEq(amount, 1038749900060143067);
    }
}
