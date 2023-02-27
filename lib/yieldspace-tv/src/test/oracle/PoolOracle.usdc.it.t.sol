// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import "../../oracle/PoolOracle.sol";

contract PoolOracleUSDCIntegrationTest is Test {
    IPoolOracle internal oracle;
    IPool internal pool = IPool(0xB2fff7FEA1D455F0BCdd38DA7DeE98af0872a13a); // FYUSDC2212

    function setUp() public {
        vm.createSelectFork("mainnet", 15313316);

        oracle = new PoolOracle(24 hours, 24, 5 minutes);

        _provideLendingLiquidity();
        oracle.updatePool(pool);
        skip(10 minutes);
    }

    function _provideLendingLiquidity() internal {
        uint128 liquidity = type(uint48).max / 1e3;
        assertEq(liquidity, 281_474.976710e6);

        deal(address(pool.fyToken()), address(this), liquidity);
        pool.fyToken().transfer(address(pool), liquidity);
        pool.sellFYToken(address(0x666), 0);
    }

    function testSellFYTokenPreview() public {
        uint128 amount = 1000e6;
        uint256 spotValue = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellFYTokenPreview(pool, amount);

        assertEqDecimal(spotValue, 998.180998e6, 6, "spotValue");
        assertEqDecimal(oracleValue, 998.181891e6, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testSellBasePreview() public {
        uint128 amount = 1000e6;
        uint256 spotValue = pool.sellBasePreview(amount);

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellBasePreview(pool, amount);

        assertEqDecimal(spotValue, 1001.470373e6, 6, "spotValue");
        assertEqDecimal(oracleValue, 1001.475094e6, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyFYTokenPreview() public {
        uint128 amount = 1000e6;
        uint256 spotValue = pool.buyFYTokenPreview(amount);

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyFYTokenPreview(pool, amount);

        assertEqDecimal(spotValue, 998.531781e6, 6, "spotValue");
        assertEqDecimal(oracleValue, 998.527077e6, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyBasePreview() public {
        uint128 amount = 1000e6;
        uint256 spotValue = pool.buyBasePreview(amount);

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyBasePreview(pool, amount);

        assertEqDecimal(spotValue, 1001.822320e6, 6, "spotValue");
        assertEqDecimal(oracleValue, 1001.821419e6, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testSellFYTokenPreviewExpired() public {
        uint128 amount = 1000e6;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellFYTokenPreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testSellBasePreviewExpired() public {
        uint128 amount = 1000e6;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellBasePreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyFYTokenPreviewExpired() public {
        uint128 amount = 1000e6;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyFYTokenPreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyBasePreviewExpired() public {
        uint128 amount = 1000e6;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyBasePreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 6, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }
}
