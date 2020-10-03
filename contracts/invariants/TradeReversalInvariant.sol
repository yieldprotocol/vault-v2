// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../pool/YieldMath.sol"; // 64 bits
import "../pool/Math64x64.sol";
import "@nomiclabs/buidler/console.sol";


contract TradeReversalInvariant {
    uint128 constant internal precision = 1e12;
    int128 constant internal k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant internal g1 = int128(uint256((950 << 64)) / 1000); // To be used when selling Dai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    int128 constant internal g2 = int128(uint256((1000 << 64)) / 950); // To be used when selling fyDai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256

    uint128 minDaiReserves = 10**21; // $1000
    uint128 minFYDaiReserves = minDaiReserves + 1;
    uint128 minTrade = minDaiReserves / 1000; // $1
    uint128 minTimeTillMaturity = 0;
    uint128 maxDaiReserves = 10**27; // $1B
    uint128 maxFYDaiReserves = maxDaiReserves + 1; // $1B
    uint128 maxTrade = maxDaiReserves / 10;
    uint128 maxTimeTillMaturity = 31556952;

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
        require(b <= a, "Pool: fyDai reserves too low");
        uint128 c = a - b;
        return c;
    }

    /// @dev Ensures that if we sell fyDai for DAI and back we get less fyDai than we had
    function testSellFYDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiIn, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 fyDaiOut = _sellFYDaiAndReverse(daiReserves, fyDaiReserves, fyDaiIn, timeTillMaturity);
        assert(fyDaiOut <= fyDaiIn);
        return fyDaiOut;
    }

    /// @dev Ensures that if we buy fyDai for DAI and back we get less DAI than we had
    function testBuyFYDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiOut, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 fyDaiIn = _buyFYDaiAndReverse(daiReserves, fyDaiReserves, fyDaiOut, timeTillMaturity);
        assert(fyDaiOut <= fyDaiIn);
        return fyDaiIn;
    }

    /// @dev Ensures that if we sell DAI for fyDai and back we get less DAI than we had
    function testSellDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiOut = _sellDaiAndReverse(daiReserves, fyDaiReserves, daiIn, timeTillMaturity);
        assert(daiOut <= daiIn);
        return daiOut;
    }

    /// @dev Ensures that if we buy DAI for fyDai and back we get less fyDai than we had
    function testBuyDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiIn = _buyFYDaiAndReverse(daiReserves, fyDaiReserves, daiOut, timeTillMaturity);
        assert(daiOut <= daiIn);
        return daiIn;
    }

    /// @dev Ensures log_2 grows as x grows
    function testLog2MonotonicallyGrows(uint128 x) internal pure {
        uint128 z1= YieldMath.log_2(x);
        uint128 z2= YieldMath.log_2(x + 1);
        assert(z2 >= z1);
    }

    /// @dev Sell fyDai and sell the obtained Dai back for fyDai
    function _sellFYDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiOutForFYDaiIn(daiReserves, fyDaiReserves, fyDaiIn, timeTillMaturity, k, g2);
        require(add(fyDaiReserves, fyDaiIn) >= sub(daiReserves, daiAmount));
        uint128 fyDaiOut = YieldMath.fyDaiOutForDaiIn(sub(daiReserves, daiAmount), add(fyDaiReserves, fyDaiIn), daiAmount, timeTillMaturity, k, g1);
        require(sub(add(fyDaiReserves, fyDaiIn), fyDaiOut) >= daiReserves);
        return fyDaiOut;
    }

    /// @dev Buy fyDai and sell it back
    function _buyFYDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiInForFYDaiOut(daiReserves, fyDaiReserves, fyDaiOut, timeTillMaturity, k, g1);
        require(sub(fyDaiReserves, fyDaiOut) >= add(daiReserves, daiAmount));
        uint128 fyDaiIn = YieldMath.fyDaiInForDaiOut(add(daiReserves, daiAmount), sub(fyDaiReserves, fyDaiOut), daiAmount, timeTillMaturity, k, g2);
        require(add(sub(fyDaiReserves, fyDaiOut), fyDaiIn) >= daiReserves);
        return fyDaiIn;
    }

    /// @dev Sell fyDai and sell the obtained Dai back for fyDai
    function _sellDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 fyDaiAmount = YieldMath.fyDaiOutForDaiIn(daiReserves, fyDaiReserves, daiIn, timeTillMaturity, k, g1);
        require(sub(fyDaiReserves, fyDaiAmount) >= add(daiReserves, daiIn));
        uint128 daiOut = YieldMath.daiOutForFYDaiIn(add(daiReserves, daiIn), sub(fyDaiReserves, fyDaiAmount), fyDaiAmount, timeTillMaturity, k, g2);
        require(fyDaiReserves >= sub(add(daiReserves, daiIn), daiOut));
        return daiOut;
    }

    /// @dev Buy fyDai and sell it back
    function _buyDaiAndReverse(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 fyDaiAmount = YieldMath.fyDaiInForDaiOut(daiReserves, fyDaiReserves, daiOut, timeTillMaturity, k, g2);
        require(add(fyDaiReserves, fyDaiAmount) >= sub(daiReserves, daiOut));
        uint128 daiIn = YieldMath.daiInForFYDaiOut(sub(daiReserves, daiOut), add(fyDaiReserves, fyDaiAmount), fyDaiAmount, timeTillMaturity, k, g1);
        require(fyDaiReserves >= add(sub(daiReserves, daiOut), daiIn));
        return daiIn;
    }
}