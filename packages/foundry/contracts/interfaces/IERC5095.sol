// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

interface IERC5095 is IERC20 {
    function underlying() external view returns (address underlyingAddress);
    function maturity() external view returns (uint256 timestamp);
    function convertToUnderlying(uint256 principalAmount) external view returns (uint256 underlyingAmount);
    function convertToPrincipal(uint256 underlyingAmount) external view returns (uint256 principalAmount);
    function maxRedeem(address holder) external view returns (uint256 maxPrincipalAmount);
    function previewRedeem(uint256 principalAmount) external returns (uint256 underlyingAmount);
    function redeem(uint256 principalAmount, address to, address from) external returns (uint256 underlyingAmount);
    function maxWithdraw(address holder) external view returns (uint256 maxUnderlyingAmount);
    function previewWithdraw(uint256 underlyingAmount) external returns (uint256 principalAmount);
    function withdraw(uint256 underlyingAmount, address to, address from) external returns (uint256 principalAmount);
}
