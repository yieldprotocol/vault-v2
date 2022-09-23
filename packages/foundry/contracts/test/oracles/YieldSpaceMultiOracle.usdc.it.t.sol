// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../utils/Mocks.sol";
import "../utils/TestConstants.sol";

import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/yieldspace-tv/src/oracle/PoolOracle.sol";

import "../../interfaces/ILadle.sol";
import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";

contract YieldSpaceMultiOracleUSDCIntegrationTest is Test, TestConstants {
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);

    IPoolOracle internal pOracle;
    YieldSpaceMultiOracle internal oracle;
    IPool internal pool;

    function setUp() public {
        vm.createSelectFork("mainnet", 15313316);

        pOracle = new PoolOracle(24 hours, 24, 5 minutes);
        oracle = new YieldSpaceMultiOracle(pOracle);

        oracle.grantRole(oracle.setSource.selector, address(0xa11ce));

        pool = IPool(ladle.pools(FYUSDC2212));

        _provideLendingLiquidity();

        vm.prank(address(0xa11ce));
        oracle.setSource(FYUSDC2212, USDC, pool);

        skip(10 minutes);
    }

    function _provideLendingLiquidity() internal {
        uint128 liquidity = type(uint48).max / 1e3;
        assertEq(liquidity, 281_474.976710e6);

        deal(address(pool.fyToken()), address(this), liquidity);
        pool.fyToken().transfer(address(pool), liquidity);
        pool.sellFYToken(address(0x666), 0);
    }

    function testDiscountBorrowingPosition() public {
        uint128 amount = 1000e6;
        uint256 actual = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 peek, uint256 peekUpdateTime) = oracle.peek(
            FYUSDC2212,
            USDC,
            amount
        );
        (uint256 get, uint256 getUpdateTime) = oracle.get(
            FYUSDC2212,
            USDC,
            amount
        );

        assertEq(actual, 998.180998e6, "actual");
        assertEq(peek, 998.181891e6, "peek");
        assertEq(peekUpdateTime, block.timestamp, "timestamp");
        assertEq(peekUpdateTime, getUpdateTime, "timestamp match");
        assertEq(peek, get, "value match");
    }

    function testDiscountLendingPosition() public {
        uint128 amount = 1000e6;
        uint256 actual = pool.sellBasePreview(amount);

        (uint256 peek, uint256 peekUpdateTime) = oracle.peek(
            USDC,
            FYUSDC2212,
            amount
        );
        (uint256 get, uint256 getUpdateTime) = oracle.get(
            USDC,
            FYUSDC2212,
            amount
        );

        assertEq(actual, 1001.470373e6, "actual");
        assertEq(peek, 1001.475094e6, "peek");
        assertEq(peekUpdateTime, block.timestamp, "timestamp");
        assertEq(peekUpdateTime, getUpdateTime, "timestamp match");
        assertEq(peek, get, "value match");
    }

}
