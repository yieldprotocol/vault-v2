// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "./TradeReversalInvariant.sol";

contract EchidnaWrapper is TradeReversalInvariant {

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function sellYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiIn, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        _sellYDaiAndReverse(daiReserves, yDAIReserves, yDaiIn, timeTillMaturity);
    }

    /// @dev Buy yDai and sell it back
    function buyYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiOut, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        _buyYDaiAndReverse(daiReserves, yDAIReserves, yDaiOut, timeTillMaturity);
    }

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function sellDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiIn, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        _sellDaiAndReverse(daiReserves, yDAIReserves, daiIn, timeTillMaturity);
    }

    /// @dev Buy yDai and sell it back
    function buyDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiOut, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        _buyDaiAndReverse(daiReserves, yDAIReserves, daiOut, timeTillMaturity);
    }
}