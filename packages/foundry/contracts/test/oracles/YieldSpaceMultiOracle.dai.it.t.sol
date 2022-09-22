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
        oracle.setSource(FYDAI2212, DAI, pool);

        skip(10 minutes);
    }

    function testDiscountBorrowingPosition() public {
        uint128 amount = 1000e18;
        uint256 actual = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 peek, uint256 peekUpdateTime) = oracle.peek(
            FYDAI2212,
            DAI,
            amount
        );
        (uint256 get, uint256 getUpdateTime) = oracle.get(
            FYDAI2212,
            DAI,
            amount
        );

        assertEq(actual, 968.791448811035957254e18, "actual");
        assertEq(peek, 968.965096873157987825e18, "peek");
        assertEq(peekUpdateTime, block.timestamp, "timestamp");
        assertEq(peekUpdateTime, getUpdateTime, "timestamp match");
        assertEq(peek, get, "value match");
    }

    function testDiscountLendingPosition() public {
        uint128 amount = 1000e18;
        uint256 actual = pool.sellBasePreview(amount);

        (uint256 peek, uint256 peekUpdateTime) = oracle.peek(
            DAI,
            FYDAI2212,
            amount
        );
        (uint256 get, uint256 getUpdateTime) = oracle.get(
            DAI,
            FYDAI2212,
            amount
        );

        assertEq(actual, 1025.713037174416877184e18, "actual");
        assertEq(peek, 1025.865469553717080957e18, "peek");
        assertEq(peekUpdateTime, block.timestamp, "timestamp");
        assertEq(peekUpdateTime, getUpdateTime, "timestamp match");
        assertEq(peek, get, "value match");
    }
}
