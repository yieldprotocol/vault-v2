// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface IEToken {
    function convertBalanceToUnderlying(uint256 balance) external view returns (uint256);

    function convertUnderlyingToBalance(uint256 underlyingAmount) external view returns (uint256);
}
