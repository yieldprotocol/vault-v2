// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../mocks/YieldMath48.sol";
import "../pool/YieldMath.sol"; // 64 bits
import "../mocks/YieldMath128.sol";

/// @dev Gives access to the YieldMath functions for several precisions
contract YieldMathMock {

    // --- 128 ---

    function fyDaiOutForDaiIn128 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.fyDaiOutForDaiIn(daiReserves, fyDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForFYDaiIn128 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.daiOutForFYDaiIn(daiReserves, fyDaiReserves, fyDaiAmount, timeTillMaturity, k, g);
    }

    function fyDaiInForDaiOut128 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.fyDaiInForDaiOut(daiReserves, fyDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForFYDaiOut128 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath128.daiInForFYDaiOut(daiReserves, fyDaiReserves, fyDaiAmount, timeTillMaturity, k, g);
    }

    function log_2_128 (uint128 x) external pure returns (uint128) {
        return YieldMath128.log_2(x);
    }

    // --- 64 ---

    function fyDaiOutForDaiIn64 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.fyDaiOutForDaiIn(daiReserves, fyDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForFYDaiIn64 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiOutForFYDaiIn(daiReserves, fyDaiReserves, fyDaiAmount, timeTillMaturity, k, g);
    }

    function fyDaiInForDaiOut64 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.fyDaiInForDaiOut(daiReserves, fyDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForFYDaiOut64 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath.daiInForFYDaiOut(daiReserves, fyDaiReserves, fyDaiAmount, timeTillMaturity, k, g);
    }

    function log_2_64 (uint128 x) external pure returns (uint128) {
        return YieldMath.log_2(x);
    }

    // --- 48 ---

    function fyDaiOutForDaiIn48 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.fyDaiOutForDaiIn(daiReserves, fyDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiOutForFYDaiIn48 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.daiOutForFYDaiIn(daiReserves, fyDaiReserves, fyDaiAmount, timeTillMaturity, k, g);
    }

    function fyDaiInForDaiOut48 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 daiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.fyDaiInForDaiOut(daiReserves, fyDaiReserves, daiAmount, timeTillMaturity, k, g);
    }

    function daiInForFYDaiOut48 (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiAmount,
        uint128 timeTillMaturity, int128 k, int128 g)
    external pure returns (uint128) {
        return YieldMath48.daiInForFYDaiOut(daiReserves, fyDaiReserves, fyDaiAmount, timeTillMaturity, k, g);
    }

    function log_2 (uint128 x) external pure returns (uint128) {
        return YieldMath48.log_2(x);
    }
}