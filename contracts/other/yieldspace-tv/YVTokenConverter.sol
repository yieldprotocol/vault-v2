// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./IConverter.sol";
import "../../oracles/yearn/IYvToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

/// @title A contract to convert between yvToken to underlying & vice versa
contract YVTokenConverter is IConverter {
    /// @notice The wrapped asset
    IYvToken wrappedAsset;

    /// @notice The asset
    IERC20 asset;

    constructor(address asset_, address wrappedAsset_) {
        wrappedAsset = IYvToken(wrappedAsset_);
        asset = IERC20(asset_);
        asset.approve(wrappedAsset_, type(uint256).max);
    }

    /* View Functions
     ******************************************************************************************************************/
    /// @notice A function to get exactly how many wrappedAsset would be obtained from wrapping assets.
    /// @param assets Amount of assets to be wrapped
    /// @return The amount of wrapped assets that would be received
    function wrappedFrom(uint256 assets) external view override returns (uint256) {
        return (assets * wrappedAsset.totalSupply()) / wrappedAsset.totalAssets();
    }

    /// @notice A function to get exactly how many asset would be obtained from unwrapping wrappedAssets
    /// @param wrappedAssets Amount of wrapped asset
    /// @return Amount of assets that would be received
    function assetFrom(uint256 wrappedAssets) external view override returns (uint256) {
        return (wrappedAssets * wrappedAsset.totalAssets()) / wrappedAsset.totalSupply();
    }

    /// @notice A function to get exactly how many wrappedAssets would need to be unwrapped to obtain assets.
    /// @param assets Amount of assets to be obtained
    /// @return Amount of wrapped assets that would be required
    function wrappedFor(uint256 assets) external view override returns (uint256) {
        return (assets * wrappedAsset.totalSupply()) / wrappedAsset.totalAssets();
    }

    /// @notice A function to get exactly how many assets would need to be wrapped to obtain wrappedAssets.
    /// @param wrappedAssets Amount of wrapped asset to be obtained
    /// @return Amount of assets that would be required
    function assetFor(uint256 wrappedAssets) external view override returns (uint256) {
        return (wrappedAssets * wrappedAsset.totalAssets()) / wrappedAsset.totalSupply();
    }

    /* Converter functions
     ******************************************************************************************************************/
    /// @notice Wraps the asset present in the contract
    /// @dev The asset to be wrapped must have been transferred to the converter before this is called
    /// @param to Address to which the wrapped asset would be sent
    /// @return wrappedAmount Amount of wrapped assets received
    function wrap(address to) external override returns (uint256 wrappedAmount) {
        uint256 amount = asset.balanceOf(address(this));
        wrappedAmount = wrappedAsset.deposit(amount, to);

        emit Wrapped(to, amount, wrappedAmount);
    }

    /// @notice Unwraps the asset present in the contract
    /// @dev The asset to be unwrapped must have been transferred to the converter before this is called
    /// @param to Address to which the unwrapped asset would be sent
    /// @return unwrappedAmount Amount of unwrapped assets received
    function unwrap(address to) external override returns (uint256 unwrappedAmount) {
        uint256 amount = IERC20(address(wrappedAsset)).balanceOf(address(this));
        unwrappedAmount = wrappedAsset.withdraw(amount, to);

        emit Unwrapped(to, amount, unwrappedAmount);
    }
}
