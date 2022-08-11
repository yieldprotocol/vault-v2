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
        oracle.setSource(FYUSDC2212, USDC, address(pool));

        skip(10 minutes);
    }

    function _provideLendingLiquidity() internal {
        uint128 liquidity = type(uint48).max / 1e3;
        assertEq(liquidity, 281_474.976710e6);

        deal(address(pool.fyToken()), address(pool), liquidity);
        pool.sellFYToken(address(0x666), 0);
    }

    function testPeekDiscountBorrowingPosition() public {
        uint128 amount = 1000e6;
        uint256 actual = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 value, uint256 updateTime) = oracle.peek(
            FYUSDC2212,
            USDC,
            amount
        );

        assertEq(actual, 998.180998e6, "actual");
        assertEq(value, 998.527077e6, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testPeekDiscountLendingPosition() public {
        uint128 amount = 1000e6;
        uint256 actual = pool.sellBasePreview(amount);

        (uint256 value, uint256 updateTime) = oracle.peek(
            USDC,
            FYUSDC2212,
            amount
        );

        assertEq(actual, 1001.470373e6, "actual");
        assertEq(value, 1001.821419e6, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testGetDiscountBorrowingPosition() public {
        uint128 amount = 1000e6;
        uint256 actual = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2212,
            USDC,
            amount
        );

        assertEq(actual, 998.180998e6, "actual");
        assertEq(value, 998.527077e6, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testGetDiscountLendingPosition() public {
        uint128 amount = 1000e6;
        uint256 actual = pool.sellBasePreview(amount);

        (uint256 value, uint256 updateTime) = oracle.get(
            USDC,
            FYUSDC2212,
            amount
        );

        assertEq(actual, 1001.470373e6, "actual");
        assertEq(value, 1001.821419e6, "value");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    // TODO restore when the liquidity can be checked
    // function testGetDiscountPosition(
    //     int32[100] memory trades,
    //     uint8[100] memory time
    // ) public {
    //     for (uint256 i = 0; i < trades.length; i++) {
    //         int32 t = trades[i] / 1e3;

    //         if (t > 1e6) {
    //             uint128 amount = uint32(t);
    //             uint256 preview = pool.unwrapPreview(
    //                 pool.sellFYTokenPreview(amount)
    //             );

    //             (uint256 oracleValue, ) = oracle.get(FYUSDC2212, USDC, amount);

    //             assertApproxEqRel(
    //                 oracleValue,
    //                 preview,
    //                 0.025e18,
    //                 "oracleValue"
    //             );

    //             deal(address(pool.fyToken()), address(pool), amount);
    //             uint256 baseOut = pool.sellFYToken(address(0x1), 0);

    //             assertApproxEqAbs(baseOut, preview, 2);

    //             // whatever amount * 30 seg (128 min max)
    //             skip(uint256(time[i]) * 30);
    //         }

    //         if (t < -1e6) {
    //             uint128 amount = uint32(-t);
    //             uint256 preview = pool.sellBasePreview(amount);

    //             (uint256 oracleValue, ) = oracle.get(USDC, FYUSDC2212, amount);

    //             assertApproxEqRel(
    //                 oracleValue,
    //                 preview,
    //                 0.025e18,
    //                 "oracleValue"
    //             );

    //             deal(address(pool.baseToken()), address(pool), amount);
    //             uint256 fyTokenOut = pool.sellBase(address(0x1), 0);

    //             assertApproxEqAbs(fyTokenOut, preview, 2);

    //             // whatever amount * 30 seg (128 min max)
    //             skip(uint256(time[i]) * 30);
    //         }
    //     }
    // }
}
