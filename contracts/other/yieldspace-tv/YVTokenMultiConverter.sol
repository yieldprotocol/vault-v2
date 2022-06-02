// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./IConverter.sol";
import "../../oracles/yearn/IYvToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

/// @title A contract to convert between yvToken to underlying & vice versa
contract YVTokenMultiConverter is IConverter, AccessControl {
    /// @notice Mapping of yvToken to underlying asset
    mapping(IYvToken => IERC20) wrappers;

    modifier supportedYV(IYvToken yvToken) {
        require(wrappers[yvToken] != IERC20(address(0)), "yvToken not supported");
        _;
    }

    /* View Functions
     ******************************************************************************************************************/
    /// @notice A function to get exactly how many yvToken would be obtained from wrapping assets.
    /// @param yvToken The yvToken for which calculation needs to be done
    /// @param assets Amount of assets to be wrapped
    /// @return The amount of wrapped assets that would be received
    function wrappedFrom(IYvToken yvToken, uint256 assets)
        external
        view
        override
        supportedYV(yvToken)
        returns (uint256)
    {
        return (assets * yvToken.totalSupply()) / yvToken.totalAssets();
    }

    /// @notice A function to get exactly how many asset would be obtained from unwrapping wrappedAssets
    /// @param yvToken The yvToken for which calculation needs to be done
    /// @param wrappedAssets Amount of wrapped asset
    /// @return Amount of assets that would be received
    function assetFrom(IYvToken yvToken, uint256 wrappedAssets)
        external
        view
        override
        supportedYV(yvToken)
        returns (uint256)
    {
        require(wrappers[yvToken] != IERC20(address(0)), "yvToken not supported");
        return (wrappedAssets * yvToken.totalAssets()) / yvToken.totalSupply();
    }

    /// @notice A function to get exactly how many wrappedAssets would need to be unwrapped to obtain assets.]
    /// @param yvToken The yvToken for which calculation needs to be done
    /// @param assets Amount of assets to be obtained
    /// @return Amount of wrapped assets that would be required
    function wrappedFor(IYvToken yvToken, uint256 assets)
        external
        view
        override
        supportedYV(yvToken)
        returns (uint256)
    {
        return (assets * yvToken.totalSupply()) / yvToken.totalAssets();
    }

    /// @notice A function to get exactly how many assets would need to be wrapped to obtain wrappedAssets.
    /// @param yvToken The yvToken for which calculation needs to be done
    /// @param wrappedAssets Amount of wrapped asset to be obtained
    /// @return Amount of assets that would be required
    function assetFor(IYvToken yvToken, uint256 wrappedAssets)
        external
        view
        override
        supportedYV(yvToken)
        returns (uint256)
    {
        return (wrappedAssets * yvToken.totalAssets()) / yvToken.totalSupply();
    }

    /* Converter functions
     ******************************************************************************************************************/
    /// @notice Wraps the asset present in the contract
    /// @dev The asset to be wrapped must have been transferred to the converter before this is called
    /// @param yvToken The yvToken to which asset would be wrapped into
    /// @param to Address to which the wrapped asset would be sent
    /// @return wrappedAmount Amount of wrapped assets received
    function wrap(IYvToken yvToken, address to) external override supportedYV(yvToken) returns (uint256 wrappedAmount) {
        IERC20 underlyingAsset = wrappers[yvToken];
        uint256 amount = underlyingAsset.balanceOf(address(this));
        wrappedAmount = yvToken.deposit(amount, to);

        emit Wrapped(yvToken, to, amount, wrappedAmount);
    }

    /// @notice Unwraps the asset present in the contract
    /// @dev The asset to be unwrapped must have been transferred to the converter before this is called
    /// @param yvToken The yvToken which would be unwrapped
    /// @param to Address to which the unwrapped asset would be sent
    /// @return unwrappedAmount Amount of unwrapped assets received
    function unwrap(IYvToken yvToken, address to)
        external
        override
        supportedYV(yvToken)
        returns (uint256 unwrappedAmount)
    {
        uint256 amount = yvToken.balanceOf(address(this));
        unwrappedAmount = yvToken.withdraw(amount, to);

        emit Unwrapped(yvToken, to, amount, unwrappedAmount);
    }

    /* Governance functions
     ******************************************************************************************************************/
    /// @notice Function to add wrapper token
    /// @param yvToken The yvToken to be added
    function addWrapper(IYvToken yvToken) external auth {
        IERC20 asset = IERC20(yvToken.token());
        wrappers[yvToken] = asset;
        asset.approve(address(yvToken), 0);
        asset.approve(address(yvToken), type(uint256).max);
    }
}
