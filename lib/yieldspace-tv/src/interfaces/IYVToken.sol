// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/src/token/IERC20.sol";

//TODO: Merge with IYvToken found in vault-v2/oracles
interface IYVToken is IERC20, IERC20Metadata {

    /// @dev Used to deposit underlying & get yvTokens in return
    function deposit(uint256 _amount, address _recipient) external returns (uint256);

    /// @notice Returns the price for a single Yearn Vault share.
    /// @dev total vault assets / total token supply (calculated not cached)
    function pricePerShare() external view returns (uint256);

    function mint(address, uint256) external;

    function token() external view returns (address);

    /// @dev Used to redeem yvTokens for underlying
    function withdraw(uint256 _amount, address _recipient) external returns (uint256);

}
