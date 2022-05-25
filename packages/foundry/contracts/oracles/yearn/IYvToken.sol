// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";

// @notice Interface for Yearn Vault tokens for use with Yield price oracles
// @dev see https://github.com/yearn/yearn-vaults/blob/main/contracts/Vault.vy
interface IYvToken is IERC20Metadata {
    // @notice Returns the price for a single Yearn Vault share.
    // @dev total vault assets / total token supply (calculated not cached)
    function pricePerShare() external view returns (uint256);

    // @dev Used to redeem yvTokens for underlying
    function withdraw() external returns (uint256);

    // @dev Returns address of underlying token
    function token() external returns (address);

}
