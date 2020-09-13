// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../mocks/YieldMath48.sol";
import "../pool/YieldMath.sol"; // 64 bits
import "../mocks/YieldMath128.sol";

/// @dev Gives access to the YieldMath functions for several precisions
contract YieldMathMock {

    // --- 128 ---

    function eDaiOutForDaiIn128 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.eDaiOutForDaiIn(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForEDaiIn128 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.daiOutForEDaiIn(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g);
    }

    function eDaiInForDaiOut128 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.eDaiInForDaiOut(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForEDaiOut128 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.daiInForEDaiOut(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g);
    }

    function log_2_128 (uint128 x) external pure returns (uint128) {
        return YieldMath128.log_2(x);
    }

    // --- 64 ---

    function eDaiOutForDaiIn64 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.eDaiOutForDaiIn(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForEDaiIn64 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiOutForEDaiIn(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g);
    }

    function eDaiInForDaiOut64 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.eDaiInForDaiOut(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForEDaiOut64 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiInForEDaiOut(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g);
    }

    function log_2_64 (uint128 x) external pure returns (uint128) {
        return YieldMath.log_2(x);
    }

    // --- 48 ---

    function eDaiOutForDaiIn48 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.eDaiOutForDaiIn(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForEDaiIn48 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.daiOutForEDaiIn(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g);
    }

    function eDaiInForDaiOut48 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.eDaiInForDaiOut(daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForEDaiOut48 (
        uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.daiInForEDaiOut(daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g);
    }

    function log_2 (uint128 x) external pure returns (uint128) {
        return YieldMath48.log_2(x);
    }
}