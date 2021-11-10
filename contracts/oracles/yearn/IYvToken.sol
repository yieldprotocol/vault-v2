// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

// @notice Interface for Yearn Vault tokens for use with Yield price oracles
// @dev see https://github.com/yearn/yearn-vaults/blob/main/contracts/Vault.vy
interface IYvToken is IERC20 {
    // @notice Returns the price for a single Yearn Vault share.
    // @dev total vault assets / total token supply (calculated not cached)
    function pricePerShare() external view returns (uint256);
}
