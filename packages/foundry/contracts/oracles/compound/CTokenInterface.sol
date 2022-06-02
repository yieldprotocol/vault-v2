
// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.16;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

interface CTokenInterface {
    /**
     * @notice Accumulator of the total earned interest rate since the opening of the market
     */
    function borrowIndex() external view returns (uint);

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external returns (uint);
    
    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint);

    /**
     * @notice Underlying asset for this CToken
     */
    function underlying() external view returns (address);
}