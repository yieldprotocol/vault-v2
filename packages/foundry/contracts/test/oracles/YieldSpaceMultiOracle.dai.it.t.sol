// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../utils/Mocks.sol";
import "../utils/TestConstants.sol";

import "@yield-protocol/yieldspace-tv/src/oracle/PoolOracle.sol";
import "@yield-protocol/yieldspace-tv/src/Pool/Pool.sol";
import "../../interfaces/ILadle.sol";

import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";

contract YieldSpaceMultiOracleDAIIntegrationTest is Test, TestConstants {
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);

    IPoolOracle internal pOracle;
    YieldSpaceMultiOracle internal oracle;
    IPool internal pool;

    function setUp() public {
        vm.createSelectFork("mainnet", 15313316);

        pOracle = new PoolOracle(24 hours, 24, 5 minutes);
        oracle = new YieldSpaceMultiOracle(pOracle);

        oracle.grantRole(oracle.setSource.selector, address(0xa11ce));

        pool = IPool(ladle.pools(FYDAI2212));

        vm.prank(address(0xa11ce));
        oracle.setSource(FYDAI2212, DAI, address(pool));

        skip(10 minutes);
    }

    function testPeekDiscountBorrowingPosition() public {
        uint128 amount = 1000e18;
        uint256 actual = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 value, uint256 updateTime) = oracle.peek(
            FYDAI2212,
            DAI,
            amount
        );

        assertEq(actual, 968.791448811035957254e18, "actual");
        assertEq(value, 974.786684685888342732e18, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testPeekDiscountLendingPosition() public {
        uint128 amount = 1000e18;
        uint256 actual = pool.sellBasePreview(amount);

        (uint256 value, uint256 updateTime) = oracle.peek(
            DAI,
            FYDAI2212,
            amount
        );

        assertEq(actual, 1025.713037174416877184e18, "actual");
        assertEq(value, 1032.028917478030299490e18, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testGetDiscountBorrowingPosition() public {
        uint128 amount = 1000e18;
        uint256 actual = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 value, uint256 updateTime) = oracle.get(
            FYDAI2212,
            DAI,
            amount
        );

        assertEq(actual, 968.791448811035957254e18, "actual");
        assertEq(value, 974.786684685888342732e18, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testGetDiscountLendingPosition() public {
        uint128 amount = 1000e18;
        uint256 actual = pool.sellBasePreview(amount);

        (uint256 value, uint256 updateTime) = oracle.get(
            DAI,
            FYDAI2212,
            amount
        );

        assertEq(actual, 1025.713037174416877184e18, "actual");
        assertEq(value, 1032.028917478030299490e18, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }
}
