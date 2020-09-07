// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "./TradeReversalInvariant.sol";
import "./ReservesValueInvariant.sol";


contract TradeReversalInvariantWrapper is TradeReversalInvariant {

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function sellYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiIn, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _sellYDaiAndReverse(daiReserves, yDAIReserves, yDaiIn, timeTillMaturity);
    }

    /// @dev Buy yDai and sell it back
    function buyYDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 yDaiOut, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _buyYDaiAndReverse(daiReserves, yDAIReserves, yDaiOut, timeTillMaturity);
    }

    /// @dev Sell yDai and sell the obtained Dai back for yDai
    function sellDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiIn, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _sellDaiAndReverse(daiReserves, yDAIReserves, daiIn, timeTillMaturity);
    }

    /// @dev Buy yDai and sell it back
    function buyDaiAndReverse(uint128 daiReserves, uint128 yDAIReserves, uint128 daiOut, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _buyDaiAndReverse(daiReserves, yDAIReserves, daiOut, timeTillMaturity);
    }
}

contract ReservesValueInvariantWrapper is ReservesValueInvariant {
    /// @dev Calculates the value of the reserves
    function reservesValue(uint128 daiReserves, uint128 yDAIReserves, uint128 timeTillMaturity)
        public view returns (uint128)
    {
        return _reservesValue(daiReserves, yDAIReserves, timeTillMaturity);
    }
}