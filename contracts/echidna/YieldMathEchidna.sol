// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../mocks/YieldMath64.sol";
import "../mocks/YieldMath128.sol";
import "../pool/YieldMath.sol"; // 48 bits
import "../pool/ABDKMath64x64.sol";
import "@nomiclabs/buidler/console.sol";


contract YieldMathEchidna {
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
    
    /// @dev Bali Overflow-protected addition, from OpenZeppelin
    function add(uint128 a, uint128 b)
        internal pure returns (uint128)
    {
        uint128 c = a + b;
        require(c >= a, "Pool: Dai reserves too high");
        return c;
    }
    /// @dev Bali Overflow-protected substraction, from OpenZeppelin
    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        require(b <= a, "Pool: yDai reserves too low");
        uint128 c = a - b;
        return c;
    }

    function testSellYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiIn, uint128 timeTillMaturity) public view returns (bool){
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 yDaiOut = sellYDaiAndReverse(daiReserves, yDAIReserves, yDaiIn, timeTillMaturity);
        assert(yDaiOut <= add(yDaiIn, precision));
    }

    function testBuyYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiOut, uint128 timeTillMaturity) public view returns (bool){
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 yDaiIn = buyYDaiAndReverse(daiReserves, yDAIReserves, yDaiOut, timeTillMaturity);
        assert(sub(yDaiOut, precision) <= yDaiIn);
    }

    function testSellDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiIn, uint128 timeTillMaturity) public view returns (bool){
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiOut = sellDaiAndReverse(daiReserves, yDAIReserves, daiIn, timeTillMaturity);
        assert(daiOut <= add(daiIn, precision));
    }

    function testBuyDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiOut, uint128 timeTillMaturity) public view returns (bool){
        require(daiReserves > yDAIReserves);
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiIn = buyYDaiAndReverse(daiReserves, yDAIReserves, daiOut, timeTillMaturity);
        assert(sub(daiOut, precision) <= daiIn);
    }

    /*
    function testLiquidityDaiOutForYDaiIn(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiIn, uint128 timeTillMaturity) public view returns (bool){
        if (daiReserves > yDAIReserves) return true;
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 reserves_0 = initialReservesValue(daiReserves, yDAIReserves, timeTillMaturity);
        uint128 daiOut= YieldMath64.daiOutForYDaiIn(daiReserves, yDAIReserves, yDaiIn, timeTillMaturity, k, g);
        uint128 reserves_1 = initialReservesValue(sub(daiReserves, daiOut), add(yDAIReserves, yDaiIn), sub(timeTillMaturity, 1));
        assert(reserves_0 < (reserves_1)); // + precision));
        return reserves_0 < (reserves_1); // + precision);
    }
    */

    /*
    function testLiquidityDaiInForYDaiOut(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiOut, uint128 timeTillMaturity) public view returns (bool){
        if (daiReserves > yDAIReserves - yDaiOut) return true;
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 reserves_0 = initialReservesValue(daiReserves, yDAIReserves, timeTillMaturity);
        uint128 daiIn= YieldMath64.daiInForYDaiOut(daiReserves, yDAIReserves, yDaiOut, timeTillMaturity, k, g);
        uint128 reserves_1 = initialReservesValue(add(daiReserves, daiIn), sub(yDAIReserves, yDaiOut), sub(timeTillMaturity, 1));
        assert(reserves_0 < (reserves_1)); // + precision));
        return reserves_0 < (reserves_1); // + precision);
    }

    function testLiquidityYDaiOutForDaiIn(uint128 daiReserves, uint128 yDAIReserves, uint128 daiIn, uint128 timeTillMaturity) public view returns (bool){
        if (daiReserves + daiIn > yDAIReserves) return true;
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 reserves_0 = initialReservesValue(daiReserves, yDAIReserves, timeTillMaturity);
        uint128 yDaiOut= YieldMath64.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiIn, timeTillMaturity, k, g);
        uint128 reserves_1 = initialReservesValue(add(daiReserves, daiIn), sub(yDAIReserves, yDaiOut), sub(timeTillMaturity, 1));
        assert(reserves_0 < (reserves_1)); // + precision));
        return reserves_0 < (reserves_1); // + precision);
    }

    function testLiquidityYDaiInForDaiOut(uint128 daiReserves, uint128 yDAIReserves, uint128 daiOut, uint128 timeTillMaturity) public view returns (bool){
        if (daiReserves > yDAIReserves) return true;
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        yDAIReserves = minYDaiReserves + yDAIReserves % maxYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 reserves_0 = initialReservesValue(daiReserves, yDAIReserves, timeTillMaturity);
        uint128 yDaiIn= YieldMath64.yDaiInForDaiOut(daiReserves, yDAIReserves, daiOut, timeTillMaturity, k, g);
        uint128 reserves_1 = initialReservesValue(sub(daiReserves, daiOut), add(yDAIReserves, yDaiIn), sub(timeTillMaturity, 1));
        assert(reserves_0 < (reserves_1)); // + precision));
        return reserves_0 < (reserves_1); // + precision);
    }
    */

    /*
    function testLog2MonotonicallyGrows(uint128 x) public view {
        uint128 z1= YieldMath64.log_2(x);
        uint128 z2= YieldMath64.log_2(x + 1);
        assert(z2 >= z1);
    }

    function testLog2PrecisionLossRoundsDown(uint128 x) public view {
        uint128 z1 = YieldMath64.log_2(x);
        uint128 z2= YieldMath64.log_2(x);
        assert(z2 >= z1);portugal
    }

    function testPow2PrecisionLossRoundsDown(uint128 x) public view {
        uint128 z1 = YieldMath64.pow_2(x);
        uint128 z2= YieldMath64.pow_2(x);
        assert(z2 >= z1);
    } */

    /**
     * Estimate in DAI the value of reserves at protocol initialization time.
     *
     * @param daiReserves DAI reserves amount
     * @param yDAIReserves yDAI reserves amount
     * @param timeTillMaturity time till maturity in seconds
     * @return estimated value of reserves
     */
    /* function initialReservesValue (
        uint128 daiReserves, uint128 yDAIReserves, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        // a = (1 - k * timeTillMaturity)
        int128 a = ABDKMath64x64.sub (0x10000000000000000, ABDKMath64x64.mul (k, ABDKMath64x64.fromUInt (timeTillMaturity)));
        require (a > 0);

        uint256 sum =
        uint256 (YieldMath64.pow (daiReserves, uint128 (a), 0x10000000000000000)) +
        uint256 (YieldMath64.pow (yDAIReserves, uint128 (a), 0x10000000000000000)) >> 1;
        require (sum < 0x100000000000000000000000000000000);

        uint256 result = uint256 (YieldMath64.pow (uint128 (sum), 0x10000000000000000, uint128 (a))) << 1;
        require (result < 0x100000000000000000000000000000000);

        return uint128 (result);
    } */

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function sellYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath64.daiOutForYDaiIn(daiReserves, yDAIReserves, yDaiIn, timeTillMaturity, k, g);
        return YieldMath64.yDaiOutForDaiIn(sub(daiReserves, daiAmount), add(yDAIReserves, yDaiIn), daiAmount, timeTillMaturity, k, g);
    }

    /// @dev Buy yDai and sell it back
    function buyYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath64.daiInForYDaiOut(daiReserves, yDAIReserves, yDaiOut, timeTillMaturity, k, g);
        return YieldMath64.yDaiInForDaiOut(add(daiReserves, daiAmount), sub(yDAIReserves, yDaiOut), daiAmount, timeTillMaturity, k, g);
    }

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function sellDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 yDaiAmount = YieldMath64.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiIn, timeTillMaturity, k, g);
        return YieldMath64.daiOutForYDaiIn(add(daiReserves, daiIn), sub(yDAIReserves, yDaiAmount), yDaiAmount, timeTillMaturity, k, g);
    }

    /// @dev Buy yDai and sell it back
    function buyDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 yDaiAmount = YieldMath64.yDaiInForDaiOut(daiReserves, yDAIReserves, daiOut, timeTillMaturity, k, g);
        return YieldMath64.daiInForYDaiOut(add(daiReserves, daiOut), sub(yDAIReserves, yDaiAmount), yDaiAmount, timeTillMaturity, k, g);
    }
}