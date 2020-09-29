// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../pool/YieldMath.sol"; // 64 bits
import "../pool/Math64x64.sol";
import "@nomiclabs/buidler/console.sol";


contract MaturityCurve {
    uint128 constant internal precision = 1e12;
    uint128 constant internal step = precision;
    int128 constant internal k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant internal g1 = int128(uint256((950 << 64)) / 1000); // To be used when selling Dai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    int128 constant internal g2 = int128(uint256((1000 << 64)) / 950); // To be used when selling eDai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256

    uint128 constant minDaiReserves = 10**21; // $1000
    uint128 constant minEDaiReserves = minDaiReserves + 1;
    uint128 constant minTimeTillMaturity = 0;
    uint128 constant maxDaiReserves = 10**27; // $1B
    uint128 constant maxEDaiReserves = maxDaiReserves + 1; // $1B
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
    /// @dev Overflow-protected substraction, from OpenZeppelin
    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        require(b <= a, "Pool: eDai reserves too low");
        uint128 c = a - b;
        return c;
    }

    function diff(uint128 a, uint128 b) internal pure returns (uint128) {
        return a > b ? a - b : b - a;
    }

    /// @dev Ensures that if we sell eDai for DAI and back we get less eDai than we had
    function testSellEDai(uint128 daiReserves, uint128 eDaiReserves, uint128 timeTillMaturity)
        public view returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 eDaiOut1 = _sellEDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity);
        uint128 eDaiOut2 = _sellEDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity + 1);
        assert(diff(eDaiOut1, eDaiOut2) < step);
        return (eDaiOut1, eDaiOut2);
    }

    /// @dev Ensures that if we buy eDai for DAI and back we get less DAI than we had
    function testBuyEDai(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiOut, uint128 timeTillMaturity)
        public view returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 eDaiIn1 = _buyEDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity);
        uint128 eDaiIn2 = _buyEDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity + 1);
        assert(diff(eDaiIn1, eDaiIn2) < step);
        return (eDaiIn1, eDaiIn2);
    }

    /// @dev Ensures that if we sell DAI for eDai and back we get less DAI than we had
    function testSellDai(uint128 daiReserves, uint128 eDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        public view returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiOut1 = _sellDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity);
        uint128 daiOut2 = _sellDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity + 1);
        assert(diff(daiOut1, daiOut2) < step);
        return (daiOut1, daiOut2);
    }

    /// @dev Ensures that if we buy DAI for eDai and back we get less eDai than we had
    function testBuyDai(uint128 daiReserves, uint128 eDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        public view returns (uint128, uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiIn1 = _buyEDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity);
        uint128 daiIn2 = _buyEDai(daiReserves, eDaiReserves, tradeSize, timeTillMaturity);
        assert(diff(daiIn1, daiIn2) < step);
        return (daiIn1, daiIn2);
    }

    /// @dev Sell eDai and sell the obtained Dai back for eDai
    function _sellEDai(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiOutForEDaiIn(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity, k, g2);
        require(add(eDaiReserves, eDaiIn) >= sub(daiReserves, daiAmount));
        uint128 eDaiOut = YieldMath.eDaiOutForDaiIn(sub(daiReserves, daiAmount), add(eDaiReserves, eDaiIn), daiAmount, timeTillMaturity, k, g1);
        require(sub(add(eDaiReserves, eDaiIn), eDaiOut) >= daiReserves);
        return eDaiOut;
    }

    /// @dev Buy eDai and sell it back
    function _buyEDai(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiInForEDaiOut(daiReserves, eDaiReserves, eDaiOut, timeTillMaturity, k, g1);
        require(sub(eDaiReserves, eDaiOut) >= add(daiReserves, daiAmount));
        uint128 eDaiIn = YieldMath.eDaiInForDaiOut(add(daiReserves, daiAmount), sub(eDaiReserves, eDaiOut), daiAmount, timeTillMaturity, k, g2);
        require(add(sub(eDaiReserves, eDaiOut), eDaiIn) >= daiReserves);
        return eDaiIn;
    }

    /// @dev Sell eDai and sell the obtained Dai back for eDai
    function _sellDai(uint128 daiReserves, uint128 eDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 eDaiAmount = YieldMath.eDaiOutForDaiIn(daiReserves, eDaiReserves, daiIn, timeTillMaturity, k, g1);
        require(sub(eDaiReserves, eDaiAmount) >= add(daiReserves, daiIn));
        uint128 daiOut = YieldMath.daiOutForEDaiIn(add(daiReserves, daiIn), sub(eDaiReserves, eDaiAmount), eDaiAmount, timeTillMaturity, k, g2);
        require(eDaiReserves >= sub(add(daiReserves, daiIn), daiOut));
        return daiOut;
    }

    /// @dev Buy eDai and sell it back
    function _buyDai(uint128 daiReserves, uint128 eDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 eDaiAmount = YieldMath.eDaiInForDaiOut(daiReserves, eDaiReserves, daiOut, timeTillMaturity, k, g2);
        require(add(eDaiReserves, eDaiAmount) >= sub(daiReserves, daiOut));
        uint128 daiIn = YieldMath.daiInForEDaiOut(sub(daiReserves, daiOut), add(eDaiReserves, eDaiAmount), eDaiAmount, timeTillMaturity, k, g1);
        require(eDaiReserves >= add(sub(daiReserves, daiOut), daiIn));
        return daiIn;
    }
}