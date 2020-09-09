// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../mocks/YieldMath48.sol";
import "../pool/YieldMath.sol"; // 64 bits
import "../mocks/YieldMath128.sol";

/// @dev Gives access to the YieldMath functions for several precisions
contract YieldMathMock {

    // --- 128 ---

    function yDaiOutForDaiIn128 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForYDaiIn128 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.daiOutForYDaiIn(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    function yDaiInForDaiOut128 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForYDaiOut128 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.daiInForYDaiOut(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    function log_2_128 (uint128 x) external pure returns (uint128) {
        return YieldMath128.log_2(x);
    }

    // --- 64 ---

    function yDaiOutForDaiIn64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForYDaiIn64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiOutForYDaiIn(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    function yDaiInForDaiOut64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.yDaiInForDaiOut(daiReserves, yDAIReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForYDaiOut64 (
        uint128 daiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiInForYDaiOut(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
    }

    function log_2_64 (uint128 x) external pure returns (uint128) {
        return YieldMath.log_2(x);
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

    function log_2 (uint128 x) external pure returns (uint128) {
        return YieldMath48.log_2(x);
    }
}