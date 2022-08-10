// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../utils/Mocks.sol";
import "../utils/TestConstants.sol";

import "@yield-protocol/yieldspace-tv/src/oracle/PoolOracle.sol";
import "../../interfaces/ILadle.sol";

import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";

contract YieldSpaceMultiOracleIntegrationTest is Test, TestConstants {
    using Mocks for *;

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
        oracle.setSource(FYUSDC2212, USDC, address(pool));

        skip(10 minutes);
    }

    function _provideLendingLiquidity() internal {
        IFYToken fyToken = IFYToken(address(pool.fyToken()));

        uint128 liquidity = type(uint48).max / 1e3;
        assertEq(liquidity, 281_474.976710e6);

        vm.prank(address(ladle));
        fyToken.mint(address(pool), liquidity);

        pool.sellFYToken(address(0x666), 0);
    }

    function testCurrentRates() public {
        uint128 amount = 1000e6;

        assertEq(
            pool.sellFYTokenPreview(amount),
            980.437196e6,
            "sellFYTokenPreview"
        );
        assertEq(pool.buyBasePreview(amount), 1001.822320e6, "buyBasePreview");

        assertEq(
            pool.buyFYTokenPreview(amount),
            998.531781e6,
            "buyFYTokenPreview"
        );
        assertEq(pool.sellBasePreview(amount), 1001.470373e6, "sellBasePreview");
    }

    // function testPeekDiscountBorrowingPosition() public {
    //     uint128 amount = 1000e6;
    //     uint256 actual = pool.sellFYTokenPreview(amount);

    //     (uint256 value, uint256 updateTime) = oracle.peek(
    //         FYUSDC2212,
    //         USDC,
    //         amount
    //     );

    //     assertEq(actual, 980.437196e6, "actual");
    //     assertEq(value, 998.183419e6, "value");
    //     assertEq(updateTime, block.timestamp, "timestamp");
    // }

    // function testPeekDiscountLendingPosition() public {
    //     uint128 amount = 1000e6;
    //     uint256 actual = pool.sellBasePreview(amount);

    //     (uint256 value, uint256 updateTime) = oracle.peek(
    //         USDC,
    //         FYUSDC2212,
    //         amount
    //     );

    //     assertEq(actual, 1001.470373e6, "actual");
    //     assertEq(value, 1001.473853e6, "value");
    //     assertEq(updateTime, block.timestamp, "timestamp");
    // }

    // function testGetDiscountBorrowingPosition() public {
    //     uint128 amount = 1000e6;
    //     uint256 actual = pool.buyFYTokenPreview(amount);

    //     (uint256 value, uint256 updateTime) = oracle.get(
    //         FYUSDC2212,
    //         USDC,
    //         amount
    //     );

    //     assertEq(actual, 998.531781e6, "actual");
    //     assertEq(value, 998.183419e6, "value");
    //     assertEq(updateTime, block.timestamp, "timestamp");
    // }

    // function testGetDiscountLendingPosition() public {
    //     uint128 amount = 1000e6;
    //     uint256 actual = pool.sellBasePreview(amount);

    //     (uint256 value, uint256 updateTime) = oracle.get(
    //         USDC,
    //         FYUSDC2212,
    //         amount
    //     );

    //     assertEq(actual, 1001.470373e6, "actual");
    //     assertEq(value, 1001.473853e6, "value");
    //     assertEq(updateTime, block.timestamp, "timestamp");
    // }
}
