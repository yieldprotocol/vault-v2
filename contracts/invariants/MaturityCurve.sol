// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../pool/YieldMath.sol"; // 64 bits
import "../pool/Math64x64.sol";
import "@nomiclabs/buidler/console.sol";


contract MaturityCurve {
    uint128 constant internal precision = 1e12;
    uint128 constant internal step = precision * 10;
    int128 constant internal k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant internal g1 = int128(uint256((950 << 64)) / 1000); // To be used when selling Dai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    int128 constant internal g2 = int128(uint256((1000 << 64)) / 950); // To be used when selling fyDai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256

    uint128 constant minDaiReserves = 10**21; // $1000
    uint128 constant minFYDaiReserves = minDaiReserves + 1;
    uint128 constant minTimeTillMaturity = 0;
    uint128 constant maxDaiReserves = 10**27; // $1B
    uint128 constant maxFYDaiReserves = maxDaiReserves + 1; // $1B
    uint128 constant maxTrade = maxDaiReserves / 10;
    uint128 constant maxTimeTillMaturity = 31556952;
    uint128 constant tradeSize = 10**18; // $1

    constructor() public {}
    
    /// @dev Overflow-protected addition, from OpenZeppelin
    function add(uint128 a, uint128 b)
        internal pure returns (uint128)
    {
        uint128 c = a + b;
        require(c >= a, "Pool: Dai reserves too high");
        return c;
    }
    /// @dev Overflow-protected subtraction, from OpenZeppelin
    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        require(b <= a, "Pool: fyDai reserves too low");
        uint128 c = a - b;
        return c;
    }

    /// @dev Difference between two numbers: c = |a - b|
    function diff(uint128 a, uint128 b) internal pure returns (uint128) {
        return a > b ? a - b : b - a;
    }

    /// @dev Ensures that if we execute the same sell fyDai trade in two consecutive seconds the Dai obtained doesn't differ more than `step`
    function testSellFYDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 timeTillMaturity)
        public pure returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 fyDaiOut1 = _sellFYDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity);
        uint128 fyDaiOut2 = _sellFYDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity + 1);
        assert(diff(fyDaiOut1, fyDaiOut2) < step);
        return (fyDaiOut1, fyDaiOut2);
    }

    /// @dev Ensures that if we execute the same buy fyDai trade in two consecutive seconds the Dai paid doesn't differ more than `step`
    function testBuyFYDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 timeTillMaturity)
        public pure returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 fyDaiIn1 = _buyFYDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity);
        uint128 fyDaiIn2 = _buyFYDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity + 1);
        assert(diff(fyDaiIn1, fyDaiIn2) < step);
        return (fyDaiIn1, fyDaiIn2);
    }

    /// @dev Ensures that if we execute the same sell Dai trade in two consecutive seconds the fyDai obtained doesn't differ more than `step`
    function testSellDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 timeTillMaturity)
        public pure returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiOut1 = _sellDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity);
        uint128 daiOut2 = _sellDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity + 1);
        assert(diff(daiOut1, daiOut2) < step);
        return (daiOut1, daiOut2);
    }

    /// @dev Ensures that if we execute the same buy Dai trade in two consecutive seconds the fyDai paid doesn't differ more than `step`
    function testBuyDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 timeTillMaturity)
        public pure returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiIn1 = _buyFYDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity);
        uint128 daiIn2 = _buyFYDai(daiReserves, fyDaiReserves, tradeSize, timeTillMaturity);
        assert(diff(daiIn1, daiIn2) < step);
        return (daiIn1, daiIn2);
    }

    /// @dev Sell fyDai
    function _sellFYDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        return YieldMath.daiOutForFYDaiIn(daiReserves, fyDaiReserves, fyDaiIn, timeTillMaturity, k, g2);
    }

    /// @dev Buy fyDai, reverting if the fyDai reserves fall below the Dai reserves
    function _buyFYDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiIn = YieldMath.daiInForFYDaiOut(daiReserves, fyDaiReserves, fyDaiOut, timeTillMaturity, k, g1);
        require(
            sub(fyDaiReserves, fyDaiOut) >= add(daiReserves, daiIn),
            "Pool: fyDai reserves too low"
        );
        return daiIn;
    }

    /// @dev Sell Dai, reverting if the fyDai reserves fall below the Dai reserves
    function _sellDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 fyDaiOut = YieldMath.fyDaiOutForDaiIn(daiReserves, fyDaiReserves, daiIn, timeTillMaturity, k, g1);
        require(
            sub(fyDaiReserves, fyDaiOut) >= add(daiReserves, daiIn),
            "Pool: fyDai reserves too low"
        );
        return fyDaiOut;
    }

    /// @dev Buy Dai
    function _buyDai(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        return YieldMath.fyDaiInForDaiOut(daiReserves, fyDaiReserves, daiOut, timeTillMaturity, k, g2);
    }
}