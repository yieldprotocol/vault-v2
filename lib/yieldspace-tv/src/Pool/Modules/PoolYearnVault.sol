// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

import "../Pool.sol";
import "../../interfaces/IYVToken.sol";

/*

  __     ___      _     _
  \ \   / (_)    | |   | |
   \ \_/ / _  ___| | __| |
    \   / | |/ _ \ |/ _` |
     | |  | |  __/ | (_| |
     |_|  |_|\___|_|\__,_|
       yieldprotocol.com

  ██████╗  ██████╗  ██████╗ ██╗  ██╗   ██╗███████╗ █████╗ ██████╗ ███╗   ██╗██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗
  ██╔══██╗██╔═══██╗██╔═══██╗██║  ╚██╗ ██╔╝██╔════╝██╔══██╗██╔══██╗████╗  ██║██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝
  ██████╔╝██║   ██║██║   ██║██║   ╚████╔╝ █████╗  ███████║██████╔╝██╔██╗ ██║██║   ██║███████║██║   ██║██║     ██║
  ██╔═══╝ ██║   ██║██║   ██║██║    ╚██╔╝  ██╔══╝  ██╔══██║██╔══██╗██║╚██╗██║╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║
  ██║     ╚██████╔╝╚██████╔╝███████╗██║   ███████╗██║  ██║██║  ██║██║ ╚████║ ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║
  ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝.SOL

*/

/// Module for using non-4626 compliant Yearn Vault tokens as base for the Yield Protocol Pool.sol AMM contract.
/// For example, Yearn Vault Dai: https://etherscan.io/address/0xC2cB1040220768554cf699b0d863A3cd4324ce32#readContract
/// @dev Since Yearn Vault tokens are not currently ERC4626 compliant, this contract inherits the Yield Pool
/// contract and overwrites the functions that are unique to Yearn Vaults.  For example getBaseCurrentPrice() function
/// calls the pricePerShare() function.  There is also logic to wrap/unwrap (deposit/redeem) Yearn Vault Tokens.
/// @title  PoolYearnVault.sol
/// @dev Deploy pool with Yearn Vault token and associated fyToken.
/// @author @devtooligan
contract PoolYearnVault is Pool {
    using TransferHelper for IERC20Like;

    constructor(
        address sharesToken_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) Pool(sharesToken_, fyToken_, ts_, g1Fee_) {}

    /// This is used by the constructor to set the base token as immutable.
    function _getBaseAsset(address sharesToken_) internal virtual override returns (IERC20Like) {
        return IERC20Like(address(IYVToken(sharesToken_).token()));
    }

    /// Returns the current price of one share.
    /// This function should be overriden by modules.
    /// @return The price of 1 share of a Yearn vault token in terms of its underlying base.
    function _getCurrentSharePrice() internal view virtual override returns (uint256) {
        return IYVToken(address(sharesToken)).pricePerShare();
    }

    /// Internal function for wrapping base tokens.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return shares The amount of wrapped tokens that are sent to the receiver.
    function _wrap(address receiver) internal virtual override returns (uint256 shares) {
        uint256 baseOut = baseToken.balanceOf(address(this));
        if (baseOut == 0) return 0;
        shares = IYVToken(address(sharesToken)).deposit(baseOut, receiver);
    }

    /// Internal function to preview how many shares will be received when depositing a given amount of base.
    /// @param base_ The amount of base tokens to preview the deposit.
    /// @return shares The amount of shares that would be returned from depositing.
    function _wrapPreview(uint256 base_) internal view virtual override returns (uint256 shares) {
        shares  = base_ * 10**baseDecimals / _getCurrentSharePrice();

    }

    /// Internal function for unwrapping unaccounted for base in this contract.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return base_ The amount of base base sent to the receiver.
    function _unwrap(address receiver) internal virtual override returns (uint256 base_) {
        uint256 surplus = _getSharesBalance() - sharesCached;
        if (surplus == 0) return 0;
        base_ = IYVToken(address(sharesToken)).withdraw(surplus, receiver);
    }

    /// Internal function to preview how many base tokens will be received when unwrapping a given amount of shares.
    /// @param shares The amount of shares to preview a redemption.
    /// @return base_ The amount of base tokens that would be returned from redeeming.
    function _unwrapPreview(uint256 shares) internal view virtual override returns (uint256 base_) {
        base_ = shares * _getCurrentSharePrice() / 10**baseDecimals;
    }
}
