// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./BaseConverter.sol";
import "../../oracles/yearn/IYvToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

contract YVTokenConverter is BaseConverter {
    IYvToken wrappedAsset;
    IERC20 asset;

    constructor(address asset_, address wrappedAsset_) {
        wrappedAsset = IYvToken(wrappedAsset_);
        asset = IERC20(asset_);
    }

    // View functions

    // Return exactly how many wrappedAsset would be obtained from wrapping assets.
    function wrappedFrom(uint256 assets) external view override returns (uint256 shares) {
        require(assets > 0);
        return (assets * wrappedAsset.totalSupply()) / wrappedAsset.totalAssets();
    }

    // Return exactly how many asset would be obtained from unwrapping wrappedAssets
    function assetFrom(uint256 wrappedAssets) external view override returns (uint256) {
        return (wrappedAssets * wrappedAsset.totalAssets()) / wrappedAsset.totalSupply();
    }

    // Return exactly how many wrappedAssets would need to be unwrapped to obtain assets.
    function wrappedFor(uint256 assets) external view override returns (uint256) {
        return (assets * wrappedAsset.totalSupply()) / wrappedAsset.totalAssets();
    }

    // Return exactly how many assets would need to be wrapped to obtain wrappedAssets.
    function assetFor(uint256 wrappedAssets) external view override returns (uint256) {
        return (wrappedAssets * wrappedAsset.totalAssets()) / wrappedAsset.totalSupply();
    }

    // State modifier functions
    function wrap(address to) external override {
        uint256 amount = asset.balanceOf(address(this));
        wrappedAsset.deposit(amount, to); // Why are we depositing as a converter?
    }

    function unwrap(address to) external override {
        uint256 amount = IERC20(address(wrappedAsset)).balanceOf(address(this));
        wrappedAsset.withdraw(amount, to); // Wouldn't the converter needs to be the depositer?
    }
}
