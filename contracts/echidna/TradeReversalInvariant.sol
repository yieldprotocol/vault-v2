// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../pool/YieldMath.sol"; // 64 bits
import "../pool/Math64x64.sol";


contract TradeReversalInvariant {
    uint128 constant internal precision = 1e12;
    int128 constant internal k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant internal g = int128(uint256((95 << 64)) / 100); // All constants are `ufixed`, to divide them they must be converted to uint256

    uint128 minDaiReserves = 10**21; // $1000
    uint128 minYDaiReserves = minDaiReserves + 1;
    uint128 minTrade = minDaiReserves / 1000; // $1
    uint128 minTimeTillMaturity = 0;
    uint128 maxDaiReserves = 10**27; // $1B
    uint128 maxYDaiReserves = maxDaiReserves + 1; // $1B
    uint128 maxTrade = maxDaiReserves / 10;
    uint128 maxTimeTillMaturity = 126144000;

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
        require(b <= a, "Pool: yDai reserves too low");
        uint128 c = a - b;
        return c;
    }

    /// @dev Ensures that if we sell yDAI for DAI and back we get less yDAI than we had
    function testSellYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiIn, uint128 timeTillMaturity)
        public view returns (bool)
    {
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 yDaiOut = _sellYDaiAndReverse(daiReserves, yDAIReserves, yDaiIn, timeTillMaturity);
        assert(yDaiOut <= yDaiIn);
    }

    /// @dev Ensures that if we buy yDAI for DAI and back we get less DAI than we had
    function testBuyYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiOut, uint128 timeTillMaturity)
        public view returns (bool)
    {
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 yDaiIn = _buyYDaiAndReverse(daiReserves, yDAIReserves, yDaiOut, timeTillMaturity);
        assert(yDaiOut <= yDaiIn);
    }

    /// @dev Ensures that if we sell DAI for yDAI and back we get less DAI than we had
    function testSellDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiIn, uint128 timeTillMaturity)
        public view returns (bool)
    {
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiOut = _sellDaiAndReverse(daiReserves, yDAIReserves, daiIn, timeTillMaturity);
        assert(daiOut <= daiIn);
    }

    /// @dev Ensures that if we buy DAI for yDAI and back we get less yDAI than we had
    function testBuyDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiOut, uint128 timeTillMaturity)
        public view returns (bool)
    {
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiIn = _buyYDaiAndReverse(daiReserves, yDAIReserves, daiOut, timeTillMaturity);
        assert(daiOut <= daiIn);
    }

    /// @dev Ensures log_2 grows as x grows
    function testLog2MonotonicallyGrows(uint128 x) internal pure {
        uint128 z1= YieldMath.log_2(x);
        uint128 z2= YieldMath.log_2(x + 1);
        assert(z2 >= z1);
    }

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function _sellYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiOutForYDaiIn(daiReserves, yDAIReserves, yDaiIn, timeTillMaturity, k, g);
        return YieldMath.yDaiOutForDaiIn(sub(daiReserves, daiAmount), add(yDAIReserves, yDaiIn), daiAmount, timeTillMaturity, k, g);
    }

    /// @dev Buy yDai and sell it back
    function _buyYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiInForYDaiOut(daiReserves, yDAIReserves, yDaiOut, timeTillMaturity, k, g);
        return YieldMath.yDaiInForDaiOut(add(daiReserves, daiAmount), sub(yDAIReserves, yDaiOut), daiAmount, timeTillMaturity, k, g);
    }

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function _sellDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 yDaiAmount = YieldMath.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiIn, timeTillMaturity, k, g);
        return YieldMath.daiOutForYDaiIn(add(daiReserves, daiIn), sub(yDAIReserves, yDaiAmount), yDaiAmount, timeTillMaturity, k, g);
    }

    /// @dev Buy yDai and sell it back
    function _buyDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 yDaiAmount = YieldMath.yDaiInForDaiOut(daiReserves, yDAIReserves, daiOut, timeTillMaturity, k, g);
        return YieldMath.daiInForYDaiOut(sub(daiReserves, daiOut), add(yDAIReserves, yDaiAmount), yDaiAmount, timeTillMaturity, k, g);
    }
}