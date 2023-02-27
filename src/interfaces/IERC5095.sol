// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/token/IERC20.sol";

interface IERC5095 is IERC20 {
    /// @dev Asset that is returned on redemption.
    function underlying() external view returns (address underlyingAddress);

    /// @dev Unix time at which redemption of fyToken for underlying are possible
    function maturity() external view returns (uint256 timestamp);

    /// @dev Converts a specified amount of principal to underlying
    function convertToUnderlying(uint256 principalAmount) external returns (uint256 underlyingAmount);

    /// @dev Converts a specified amount of underlying to principal
    function convertToPrincipal(uint256 underlyingAmount) external returns (uint256 principalAmount);

    /// @dev Gives the maximum amount an address holder can redeem in terms of the principal
    function maxRedeem(address holder) external view returns (uint256 maxPrincipalAmount);

    /// @dev Gives the amount in terms of underlying that the princiapl amount can be redeemed for plus accrual
    function previewRedeem(uint256 principalAmount) external returns (uint256 underlyingAmount);

    /// @dev Burn fyToken after maturity for an amount of principal.
    function redeem(uint256 principalAmount, address to, address from) external returns (uint256 underlyingAmount);

    /// @dev Gives the maximum amount an address holder can withdraw in terms of the underlying
    function maxWithdraw(address holder) external returns (uint256 maxUnderlyingAmount);

    /// @dev Gives the amount in terms of principal that the underlying amount can be withdrawn for plus accrual
    function previewWithdraw(uint256 underlyingAmount) external returns (uint256 principalAmount);

    /// @dev Burn fyToken after maturity for an amount of underlying.
    function withdraw(uint256 underlyingAmount, address to, address from) external returns (uint256 principalAmount);
}
