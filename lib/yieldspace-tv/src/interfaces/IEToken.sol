// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/src/token/IERC20.sol";

interface IEToken is IERC20, IERC20Metadata {

    /// @notice Convert an eToken balance to an underlying amount, taking into account current exchange rate
    /// @param balance eToken balance, in internal book-keeping units (18 decimals)
    /// @return Amount in underlying units, (same decimals as underlying token)
    function convertBalanceToUnderlying(uint balance) external view returns (uint);


    /// @notice Convert an underlying amount to an eToken balance, taking into account current exchange rate
    /// @param underlyingAmount Amount in underlying units (same decimals as underlying token)
    /// @return eToken balance, in internal book-keeping units (18 decimals)
    function convertUnderlyingToBalance(uint underlyingAmount) external view returns (uint);

    /// @notice Transfer underlying tokens from sender to the Euler pool, and increase account's eTokens.
    /// @param subAccountId 0 for primary, 1-255 for a sub-account.
    /// @param amount In underlying units (use max uint256 for full underlying token balance).
    /// subAccountId is the id of optional subaccounts that can be used by the depositor.
    function deposit(uint subAccountId, uint amount) external;

    function underlyingAsset() external view returns (address);

    /// @notice Transfer underlying tokens from Euler pool to sender, and decrease account's eTokens
    /// @param subAccountId 0 for primary, 1-255 for a sub-account
    /// @param amount In underlying units (use max uint256 for full pool balance)
    function withdraw(uint subAccountId, uint amount) external;

}
