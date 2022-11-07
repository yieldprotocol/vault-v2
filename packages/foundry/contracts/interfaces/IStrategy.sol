// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

interface IStrategy {
    /// @notice Returns LP tokens owned by the strategy after the last operation
    /// @return LP tokens amount
    function cached() external view returns (uint256);

    /// @notice Returns total supply of the strategy token
    /// @return Total Supply of strategy token
    function totalSupply() external view returns (uint256);

    /// @notice Returns baseId of the strategy
    /// @return baseId
    function baseId() external view returns (bytes6);
}
