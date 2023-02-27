// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import "../../../interfaces/IPool.sol";

contract NegativeRatesIntegrationTest is Test {
    IPool constant fyETH2212Pool = IPool(0x7F0dD461D77F84cDd3ceD46F9D550e35F1969a24);
    IPool constant fyDAI2212Pool = IPool(0x25e46aD1cC867c5253a179F45e1aB46144c8aBc0);
    IPool constant fyUSDC2212Pool = IPool(0x81Ae3D05e4F0d0DD29d6840424a0b761A7fdB51c);

    function setUp() public {
        vm.createSelectFork("arbitrum", 28532928);
    }

    function testSellFYTokenPreviewFYETH2212(uint128 fyTokenIn) public {
        fyTokenIn = uint128(bound(fyTokenIn, 1e12, fyETH2212Pool.maxFYTokenIn()));

        uint256 baseOut = fyETH2212Pool.sellFYTokenPreview(fyTokenIn);
        assertLe(baseOut, fyTokenIn, "baseOut < fyTokenIn");
    }

    function testSellBasePreviewFYETH2212(uint128 baseIn) public {
        baseIn = uint128(bound(baseIn, 1e12, fyETH2212Pool.maxBaseIn()));

        uint256 fyTokenOut = fyETH2212Pool.sellBasePreview(baseIn);
        assertGe(fyTokenOut, baseIn, "fyTokenOut > baseIn");
    }

    function testBuyFYTokenPreviewFYETH2212(uint128 fyTokenOut) public {
        fyTokenOut = uint128(bound(fyTokenOut, 1e12, fyETH2212Pool.maxFYTokenOut()));

        uint256 baseIn = fyETH2212Pool.buyFYTokenPreview(fyTokenOut);
        assertLe(baseIn, fyTokenOut, "baseIn < fyTokenOut");
    }

    function testBuyBasePreviewFYETH2212(uint128 baseOut) public {
        baseOut = uint128(bound(baseOut, 1e12, fyETH2212Pool.maxBaseOut()));

        uint256 fyTokenIn = fyETH2212Pool.buyBasePreview(baseOut);
        assertGe(fyTokenIn, baseOut, "fyTokenIn > baseOut");
    }

    function testSellFYTokenPreviewFYDAI2212(uint128 fyTokenIn) public {
        fyTokenIn = uint128(bound(fyTokenIn, 1e12, fyDAI2212Pool.maxFYTokenIn()));

        uint256 baseOut = fyDAI2212Pool.sellFYTokenPreview(fyTokenIn);
        assertLe(baseOut, fyTokenIn, "baseOut < fyTokenIn");
    }

    function testSellBasePreviewFYDAI2212(uint128 baseIn) public {
        baseIn = uint128(bound(baseIn, 1e12, fyDAI2212Pool.maxBaseIn()));

        uint256 fyTokenOut = fyDAI2212Pool.sellBasePreview(baseIn);
        assertGe(fyTokenOut, baseIn, "fyTokenOut > baseIn");
    }

    function testBuyFYTokenPreviewFYDAI2212(uint128 fyTokenOut) public {
        fyTokenOut = uint128(bound(fyTokenOut, 1e12, fyDAI2212Pool.maxFYTokenOut()));

        uint256 baseIn = fyDAI2212Pool.buyFYTokenPreview(fyTokenOut);
        assertLe(baseIn, fyTokenOut, "baseIn < fyTokenOut");
    }

    function testBuyBasePreviewFYDAI2212(uint128 baseOut) public {
        baseOut = uint128(bound(baseOut, 1e12, fyDAI2212Pool.maxBaseOut()));

        uint256 fyTokenIn = fyDAI2212Pool.buyBasePreview(baseOut);
        assertGe(fyTokenIn, baseOut, "fyTokenIn > baseOut");
    }

    function testSellFYTokenPreviewFYUSDC2212(uint128 fyTokenIn) public {
        fyTokenIn = uint128(bound(fyTokenIn, 1e3, fyUSDC2212Pool.maxFYTokenIn()));

        uint256 baseOut = fyUSDC2212Pool.sellFYTokenPreview(fyTokenIn);
        assertLe(baseOut, fyTokenIn, "baseOut < fyTokenIn");
    }

    function testSellBasePreviewFYUSDC2212(uint128 baseIn) public {
        baseIn = uint128(bound(baseIn, 1e3, fyUSDC2212Pool.maxBaseIn()));

        uint256 fyTokenOut = fyUSDC2212Pool.sellBasePreview(baseIn);
        assertGe(fyTokenOut, baseIn, "fyTokenOut > baseIn");
    }

    function testBuyFYTokenPreviewFYUSDC2212(uint128 fyTokenOut) public {
        fyTokenOut = uint128(bound(fyTokenOut, 1e3, fyUSDC2212Pool.maxFYTokenOut()));

        uint256 baseIn = fyUSDC2212Pool.buyFYTokenPreview(fyTokenOut);
        assertLe(baseIn, fyTokenOut, "baseIn < fyTokenOut");
    }

    function testBuyBasePreviewFYUSDC2212(uint128 baseOut) public {
        baseOut = uint128(bound(baseOut, 1e3, fyUSDC2212Pool.maxBaseOut()));

        uint256 fyTokenIn = fyUSDC2212Pool.buyBasePreview(baseOut);
        assertGe(fyTokenIn, baseOut, "fyTokenIn > baseOut");
    }
}
