// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../pool/YieldMath.sol";     // 64 bits (for trading)
import "../mocks/YieldMath128.sol"; // 128 bits (for reserves calculation)
import "../pool/Math64x64.sol";
import "@nomiclabs/buidler/console.sol";


contract WhitepaperInvariant {
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

    /// @dev Ensures that reserves grow with any daiOutForFYDaiIn trade.
    function testLiquiditfyDaiOutForFYDaiIn(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiIn, uint128 timeTillMaturity)
        public view returns (bool)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;
        require (daiReserves <= fyDaiReserves);

        uint128 whitepaperInvariant_0 = _whitepaperInvariant(daiReserves, fyDaiReserves, timeTillMaturity);
        uint128 daiOut = YieldMath.daiOutForFYDaiIn(daiReserves, fyDaiReserves, fyDaiIn, timeTillMaturity, k, g2);
        require(add(fyDaiReserves, fyDaiIn) >= sub(daiReserves, daiOut));
        uint128 whitepaperInvariant_1 = _whitepaperInvariant(sub(daiReserves, daiOut), add(fyDaiReserves, fyDaiIn), sub(timeTillMaturity, 1));
        assert(whitepaperInvariant_0 < whitepaperInvariant_1);
        return whitepaperInvariant_0 < whitepaperInvariant_1;
    }

    /// @dev Ensures that reserves grow with any fyDaiInForDaiOut trade.
    function testLiquiditfyDaiInForFYDaiOut(uint128 daiReserves, uint128 fyDaiReserves, uint128 fyDaiOut, uint128 timeTillMaturity)
        public view returns (bool)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;
        require (daiReserves <= fyDaiReserves - fyDaiOut);

        uint128 whitepaperInvariant_0 = _whitepaperInvariant(daiReserves, fyDaiReserves, timeTillMaturity);
        uint128 daiIn = YieldMath.daiInForFYDaiOut(daiReserves, fyDaiReserves, fyDaiOut, timeTillMaturity, k, g1);
        require(sub(fyDaiReserves, fyDaiOut) >= add(daiReserves, daiIn));
        uint128 whitepaperInvariant_1 = _whitepaperInvariant(add(daiReserves, daiIn), sub(fyDaiReserves, fyDaiOut), sub(timeTillMaturity, 1));
        assert(whitepaperInvariant_0 < whitepaperInvariant_1);
        return whitepaperInvariant_0 < whitepaperInvariant_1;
    }

    /// @dev Ensures that reserves grow with any fyDaiOutForDaiIn trade.
    function testLiquidityFYDaiOutForDaiIn(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        public view returns (bool)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;
        require (daiReserves + daiIn <= fyDaiReserves);

        uint128 whitepaperInvariant_0 = _whitepaperInvariant(daiReserves, fyDaiReserves, timeTillMaturity);
        uint128 fyDaiOut = YieldMath.fyDaiOutForDaiIn(daiReserves, fyDaiReserves, daiIn, timeTillMaturity, k, g1);
        require(sub(fyDaiReserves, fyDaiOut) >= add(daiReserves, daiIn));
        uint128 whitepaperInvariant_1 = _whitepaperInvariant(add(daiReserves, daiIn), sub(fyDaiReserves, fyDaiOut), sub(timeTillMaturity, 1));
        assert(whitepaperInvariant_0 < whitepaperInvariant_1);
        return whitepaperInvariant_0 < whitepaperInvariant_1;
    }

    /// @dev Ensures that reserves grow with any fyDaiInForDaiOut trade.
    function testLiquidityFYDaiInForDaiOut(uint128 daiReserves, uint128 fyDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        public view returns (bool)
    {
        daiReserves = minDaiReserves + daiReserves % maxDaiReserves;
        fyDaiReserves = minFYDaiReserves + fyDaiReserves % maxFYDaiReserves;
        timeTillMaturity = minTimeTillMaturity + timeTillMaturity % maxTimeTillMaturity;
        require (daiReserves <= fyDaiReserves);
        
        uint128 whitepaperInvariant_0 = _whitepaperInvariant(daiReserves, fyDaiReserves, timeTillMaturity);
        uint128 fyDaiIn = YieldMath.fyDaiInForDaiOut(daiReserves, fyDaiReserves, daiOut, timeTillMaturity, k, g2);
        require(add(fyDaiReserves, fyDaiIn) >= sub(daiReserves, daiOut));
        uint128 whitepaperInvariant_1 = _whitepaperInvariant(sub(daiReserves, daiOut), add(fyDaiReserves, fyDaiIn), sub(timeTillMaturity, 1));
        assert(whitepaperInvariant_0 < whitepaperInvariant_1);
        return whitepaperInvariant_0 < whitepaperInvariant_1;
    }

    /// @dev Ensures log_2 grows as x grows
    function testLog2MonotonicallyGrows(uint128 x) internal pure {
        uint128 z1= YieldMath.log_2(x);
        uint128 z2= YieldMath.log_2(x + 1);
        assert(z2 >= z1);
    }

    /**
     * Estimate in DAI the value of reserves at protocol initialization time.
     *
     * @param daiReserves DAI reserves amount
     * @param fyDaiReserves fyDai reserves amount
     * @param timeTillMaturity time till maturity in seconds
     * @return estimated value of reserves
     */
    function _whitepaperInvariant (
        uint128 daiReserves, uint128 fyDaiReserves, uint128 timeTillMaturity)
        internal pure returns (uint128)
    {
        // a = (1 - k * timeTillMaturity)
        int128 a = Math64x64.sub (0x10000000000000000, Math64x64.mul (k, Math64x64.fromUInt (timeTillMaturity)));
        require (a > 0);

        uint256 sum =
        uint256 (YieldMath128.pow (daiReserves, uint128 (a), 0x10000000000000000)) +
        uint256 (YieldMath128.pow (fyDaiReserves, uint128 (a), 0x10000000000000000)) >> 1;
        require (sum < 0x100000000000000000000000000000000);

        uint256 result = uint256 (YieldMath128.pow (uint128 (sum), 0x10000000000000000, uint128 (a))) << 1;
        require (result < 0x100000000000000000000000000000000);

        return uint128 (result);
    }
}