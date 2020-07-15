pragma solidity ^0.6.10;

import "../market/YieldMath.sol";
import "../mocks/YieldMath64.sol";
import "../mocks/YieldMath48.sol";


contract YieldMathMock {
    function yDaiOutForChaiIn (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 chaiAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath.yDaiOutForChaiIn(chaiReserves, yDAIReserves, chaiAmount, timeTillMaturity, k, c, g);
    }

    function chaiOutForYDaiIn (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath.chaiOutForYDaiIn(chaiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, c, g);
    }

    function yDaiInForChaiOut (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 chaiAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath.yDaiInForChaiOut(chaiReserves, yDAIReserves, chaiAmount, timeTillMaturity, k, c, g);
    }

    function chaiInForYDaiOut (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath.chaiInForYDaiOut(chaiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, c, g);
    }

    // --- 64 ---

    function yDaiOutForChaiIn64 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 chaiAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath64.yDaiOutForChaiIn(chaiReserves, yDAIReserves, chaiAmount, timeTillMaturity, k, c, g);
    }

    function chaiOutForYDaiIn64 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath64.chaiOutForYDaiIn(chaiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, c, g);
    }

    function yDaiInForChaiOut64 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 chaiAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath64.yDaiInForChaiOut(chaiReserves, yDAIReserves, chaiAmount, timeTillMaturity, k, c, g);
    }

    function chaiInForYDaiOut64 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath64.chaiInForYDaiOut(chaiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, c, g);
    }

    // --- 48 ---

    function yDaiOutForChaiIn48 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 chaiAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath48.yDaiOutForChaiIn(chaiReserves, yDAIReserves, chaiAmount, timeTillMaturity, k, c, g);
    }

    function chaiOutForYDaiIn48 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath48.chaiOutForYDaiIn(chaiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, c, g);
    }

    function yDaiInForChaiOut48 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 chaiAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath48.yDaiInForChaiOut(chaiReserves, yDAIReserves, chaiAmount, timeTillMaturity, k, c, g);
    }

    function chaiInForYDaiOut48 (
        uint128 chaiReserves, uint128 yDAIReserves, uint128 yDAIAmount,
        uint128 timeTillMaturity, int128 k, int128 c, int128 g)
    external pure returns (uint128) {
        return YieldMath48.chaiInForYDaiOut(chaiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, c, g);
    }
}