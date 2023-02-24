// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import "../../oracle/PoolOracle.sol";

contract PoolOracleDAIIntegrationTest is Test {
    IPoolOracle internal oracle;
    IPool internal pool = IPool(0x52956Fb3DC3361fd24713981917f2B6ef493DCcC); // FYDAI2212

    function setUp() public {
        vm.createSelectFork("mainnet", 15313316);

        oracle = new PoolOracle(24 hours, 24, 5 minutes);

        oracle.updatePool(pool);
        skip(10 minutes);
    }

    function testSellFYTokenPreview() public {
        uint128 amount = 1000e18;
        uint256 spotValue = pool.unwrapPreview(pool.sellFYTokenPreview(amount));

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellFYTokenPreview(pool, amount);

        assertEqDecimal(spotValue, 968.791448811035957254e18, 18, "spotValue");
        assertEqDecimal(oracleValue, 968.965096873157987825e18, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testSellBasePreview() public {
        uint128 amount = 1000e18;
        uint256 spotValue = pool.sellBasePreview(amount);

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellBasePreview(pool, amount);

        assertEqDecimal(spotValue, 1025.713037174416877184e18, 18, "spotValue");
        assertEqDecimal(oracleValue, 1025.865469553717080957e18, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyFYTokenPreview() public {
        uint128 amount = 1000e18;
        uint256 spotValue = pool.buyFYTokenPreview(amount);

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyFYTokenPreview(pool, amount);

        assertEqDecimal(spotValue, 974.927984428652130438e18, 18, "spotValue");
        assertEqDecimal(oracleValue, 974.786684685888342732e18, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyBasePreview() public {
        uint128 amount = 1000e18;
        uint256 spotValue = pool.buyBasePreview(amount);

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyBasePreview(pool, amount);

        assertEqDecimal(spotValue, 1032.219978677199507417e18, 18, "spotValue");
        assertEqDecimal(oracleValue, 1032.028917478030299490e18, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testSellFYTokenPreviewExpired() public {
        uint128 amount = 1000e18;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellFYTokenPreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testSellBasePreviewExpired() public {
        uint128 amount = 1000e18;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getSellBasePreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyFYTokenPreviewExpired() public {
        uint128 amount = 1000e18;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyFYTokenPreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }

    function testBuyBasePreviewExpired() public {
        uint128 amount = 1000e18;

        vm.warp(pool.maturity());

        (uint256 oracleValue, uint256 updateTime) = oracle.getBuyBasePreview(pool, amount);

        assertEqDecimal(oracleValue, amount, 18, "oracleValue");
        assertEq(updateTime, block.timestamp, "timestamp");
    }
}
