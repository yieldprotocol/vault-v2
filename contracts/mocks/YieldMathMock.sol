// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../market/YieldMath.sol";
import "../mocks/YieldMath64.sol";
import "../mocks/YieldMath48.sol";


contract YieldMathMock {
    function yDaiOutForDaiIn (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForYDaiIn (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiOutForYDaiIn(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    function yDaiInForDaiOut (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForYDaiOut (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiInForYDaiOut(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    // --- 64 ---

    function yDaiOutForDaiIn64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath64.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForYDaiIn64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath64.daiOutForYDaiIn(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    function yDaiInForDaiOut64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath64.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForYDaiOut64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath64.daiInForYDaiOut(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    // --- 48 ---

    function yDaiOutForDaiIn48 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForYDaiIn48 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.daiOutForYDaiIn(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    function yDaiInForDaiOut48 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForYDaiOut48 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.daiInForYDaiOut(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }
}