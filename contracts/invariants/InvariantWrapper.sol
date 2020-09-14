// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "./TradeReversalInvariant.sol";
import "./WhitepaperInvariant.sol";


contract TradeReversalInvariantWrapper is TradeReversalInvariant {

    /// @dev Sell eDai and sell the obtained Dai back for eDai
    function sellEDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiIn, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _sellEDaiAndReverse(daiReserves, eDaiReserves, eDaiIn, timeTillMaturity);
    }

    /// @dev Buy eDai and sell it back
    function buyEDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiOut, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _buyEDaiAndReverse(daiReserves, eDaiReserves, eDaiOut, timeTillMaturity);
    }

    /// @dev Sell eDai and sell the obtained Dai back for eDai
    function sellDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 daiIn, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _sellDaiAndReverse(daiReserves, eDaiReserves, daiIn, timeTillMaturity);
    }

    /// @dev Buy eDai and sell it back
    function buyDaiAndReverse(uint128 daiReserves, uint128 eDaiReserves, uint128 daiOut, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _buyDaiAndReverse(daiReserves, eDaiReserves, daiOut, timeTillMaturity);
    }
}

contract WhitepaperInvariantWrapper is WhitepaperInvariant {
    /// @dev Calculates the value of the reserves
    function whitepaperInvariant(uint128 daiReserves, uint128 eDaiReserves, uint128 timeTillMaturity)
        public pure returns (uint128)
    {
        return _whitepaperInvariant(daiReserves, eDaiReserves, timeTillMaturity);
    }
}