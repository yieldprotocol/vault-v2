// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../pool/YieldMath.sol"; // 64 bits
import "../pool/Math64x64.sol";
import "@nomiclabs/buidler/console.sol";


contract TradeReversalInvariant {
    uint128 constant internal precision = 1e12;
    int128 constant internal k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant internal g1 = int128(uint256((950 << 64)) / 1000); // To be used when selling Dai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    int128 constant internal g2 = int128(uint256((1000 << 64)) / 950); // To be used when selling eDai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256

    uint128 minDaiReserves = 10**21; // $1000
    uint128 minEDaiReserves = minDaiReserves + 1;
    uint128 minTrade = minDaiReserves / 1000; // $1
    uint128 minTimeTillMaturity = 0;
    uint128 maxDaiReserves = 10**27; // $1B
    uint128 maxEDaiReserves = maxDaiReserves + 1; // $1B
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
        require(b <= a, "Pool: eDai reserves too low");
        uint128 c = a - b;
        return c;
    }

    /// @dev Ensures that if we sell eDai for DAI and back we get less eDai than we had
    function testSellEDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiIn, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 eDaiOut = _sellEDaiAndReverse(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity);
        assert(eDaiOut <= eDaiIn);
        return eDaiOut;
    }

    /// @dev Ensures that if we buy eDai for DAI and back we get less DAI than we had
    function testBuyEDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiOut, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 eDaiIn = _buyEDaiAndReverse(daiReserves, eDaiReserves, eDaiOut, timeTillMaturity);
        assert(eDaiOut <= eDaiIn);
        return eDaiIn;
    }

    /// @dev Ensures that if we sell DAI for eDai and back we get less DAI than we had
    function testSellDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiOut = _sellDaiAndReverse(daiReserves, eDaiReserves, daiIn, timeTillMaturity);
        assert(daiOut <= daiIn);
        return daiOut;
    }

    /// @dev Ensures that if we buy DAI for eDai and back we get less eDai than we had
    function testBueDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        eDaiReserves = minEDaiReserves + eDaiReserves % maxEDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;

        uint128 daiIn = _buyEDaiAndReverse(daiReserves, eDaiReserves, daiOut, timeTillMaturity);
        assert(daiOut <= daiIn);
        return daiIn;
    }

    /// @dev Ensures log_2 grows as x grows
    function testLog2MonotonicallyGrows(uint128 x) internal pure {
        uint128 z1= YieldMath.log_2(x);
        uint128 z2= YieldMath.log_2(x + 1);
        assert(z2 >= z1);
    }

    /// @dev Sell eDai and sell the obtained Dai back for eDai
    function _sellEDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiOutForEDaiIn(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity, k, g2);
        require(add(eDaiReserves, eDaiIn) >= sub(daiReserves, daiAmount));
        uint128 eDaiOut = YieldMath.eDaiOutForDaiIn(sub(daiReserves, daiAmount), add(eDaiReserves, eDaiIn), daiAmount, timeTillMaturity, k, g1);
        require(sub(add(eDaiReserves, eDaiIn), eDaiOut) >= daiReserves);
        return eDaiOut;
    }

    /// @dev Buy eDai and sell it back
    function _buyEDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 daiAmount = YieldMath.daiInForEDaiOut(daiReserves, eDaiReserves, eDaiOut, timeTillMaturity, k, g1);
        require(sub(eDaiReserves, eDaiOut) >= add(daiReserves, daiAmount));
        uint128 eDaiIn = YieldMath.eDaiInForDaiOut(add(daiReserves, daiAmount), sub(eDaiReserves, eDaiOut), daiAmount, timeTillMaturity, k, g2);
        require(add(sub(eDaiReserves, eDaiOut), eDaiIn) >= daiReserves);
        return eDaiIn;
    }

    /// @dev Sell eDai and sell the obtained Dai back for eDai
    function _sellDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 eDaiAmount = YieldMath.eDaiOutForDaiIn(daiReserves, eDaiReserves, daiIn, timeTillMaturity, k, g1);
        require(sub(eDaiReserves, eDaiAmount) >= add(daiReserves, daiIn));
        uint128 daiOut = YieldMath.daiOutForEDaiIn(add(daiReserves, daiIn), sub(eDaiReserves, eDaiAmount), eDaiAmount, timeTillMaturity, k, g2);
        require(eDaiReserves >= sub(add(daiReserves, daiIn), daiOut));
        return daiOut;
    }

    /// @dev Buy eDai and sell it back
    function _bueDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        uint128 eDaiAmount = YieldMath.eDaiInForDaiOut(daiReserves, eDaiReserves, daiOut, timeTillMaturity, k, g2);
        require(add(eDaiReserves, eDaiAmount) >= sub(daiReserves, daiOut));
        uint128 daiIn = YieldMath.daiInForEDaiOut(sub(daiReserves, daiOut), add(eDaiReserves, eDaiAmount), eDaiAmount, timeTillMaturity, k, g1);
        require(eDaiReserves >= add(sub(daiReserves, daiOut), daiIn));
        return daiIn;
    }
}