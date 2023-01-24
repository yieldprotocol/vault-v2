// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 */
interface IUSDT is IERC20 {
    /**
     * @dev Returns the basisPointsRate of the token.
     */

    function basisPointsRate() external view returns (uint256);

    /**
     * @dev Returns the maximumFee of the token.
     */
    function maximumFee() external view returns (uint256);
}