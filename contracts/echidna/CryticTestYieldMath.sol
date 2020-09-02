// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../pool/YieldMath.sol"; 


contract CryticTestYieldMath {
    uint128 internal oneDAI = 10**18;
    uint128 internal tol = 10 * oneDAI;
    int128 constant internal k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant internal g = 2**64; // No fees
    constructor() public {}
    function equalWithTol(uint128 x, uint128 y) internal view returns (bool) {
        if (x > y)
            return (x - y) < tol;
        else 
            return (y - x) < tol; 
    }
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
    function DaiInOut(uint128 daiReserves, uint128 yDAIReserves, uint128 daiAmount, uint128 timeTillMaturity) public view {
        daiReserves = 1 + daiReserves % 2**112;
        yDAIReserves = 1 + yDAIReserves % 2**112;
        daiAmount = 1 + daiAmount % 2**112;
        timeTillMaturity = 1 + timeTillMaturity % (12*4*2 weeks); // 2 years
        require(daiReserves >= 1024*oneDAI);
        require(yDAIReserves >= daiReserves);
        uint128 daiAmount1 = daiAmount;
        uint128 yDAIAmount = YieldMath.yDaiOutForDaiIn(daiReserves, yDAIReserves, daiAmount1, timeTillMaturity, k, g);
        require(
            sub(yDAIReserves, yDAIAmount) >= add(daiReserves, daiAmount1),
            "Pool: yDai reserves too low"
        );
        uint128 daiAmount2 = YieldMath.daiInForYDaiOut(daiReserves, yDAIReserves, yDAIAmount, timeTillMaturity, k, g);
        require(
            sub(yDAIReserves, yDAIAmount) >= add(daiReserves, daiAmount2),
            "Pool: yDai reserves too low"
        );
        assert(equalWithTol(daiAmount1, daiAmount2));
    }
}