// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;
import "../Pool.sol";/*

  __     ___      _     _
  \ \   / (_)    | |   | |
   \ \_/ / _  ___| | __| |
    \   / | |/ _ \ |/ _` |
     | |  | |  __/ | (_| |
     |_|  |_|\___|_|\__,_|
       yieldprotocol.com

  ██████╗  ██████╗  ██████╗ ██╗     ███╗   ██╗ ██████╗ ███╗   ██╗████████╗██╗   ██╗
  ██╔══██╗██╔═══██╗██╔═══██╗██║     ████╗  ██║██╔═══██╗████╗  ██║╚══██╔══╝██║   ██║
  ██████╔╝██║   ██║██║   ██║██║     ██╔██╗ ██║██║   ██║██╔██╗ ██║   ██║   ██║   ██║
  ██╔═══╝ ██║   ██║██║   ██║██║     ██║╚██╗██║██║   ██║██║╚██╗██║   ██║   ╚██╗ ██╔╝
  ██║     ╚██████╔╝╚██████╔╝███████╗██║ ╚████║╚██████╔╝██║ ╚████║   ██║    ╚████╔╝
  ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝     ╚═══╝ .SOL
*/

/// Module for using non tokenized vault tokens as "shares" for the Yield Protocol Pool.sol AMM contract.
/// For example ordinary DAI, as opposed to yvDAI or eDAI.
/// @title  PoolNonTv.sol
/// @dev Deploy pool with base token and associated fyToken.
/// @author @devtooligan
contract PoolNonTv is Pool {
    using TransferHelper for IERC20Like;
    using Cast for uint256;

    constructor(
        address base_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) Pool(base_, fyToken_, ts_, g1Fee_) {}

    /* EXTERNAL FUNCTIONS
     *****************************************************************************************************************/

    /// Retrieve any shares/base tokens not accounted for in the cache.
    /// Note: For PoolNonTv, sharesToken == baseToken.
    /// This fn is the same as retrieveBase().
    /// @param to Address of the recipient of the shares/base tokens.
    /// @return retrieved The amount of shares/base tokens sent.
    function retrieveShares(address to) external virtual override returns (uint128 retrieved) {
        retrieved = _retrieveBase(to);
    }

    /// Retrieve any shares/base tokens not accounted for in the cache.
    /// Note: For PoolNonTv, sharesToken == baseToken.
    /// This fn is the same as retrieveShares().
    /// @param to Address of the recipient of the shares/base tokens.
    /// @return retrieved The amount of shares/base tokens sent.
    function retrieveBase(address to) external virtual override returns (uint128 retrieved) {
        retrieved = _retrieveBase(to);
    }

    /* INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    /// Retrieve any shares/base tokens not accounted for in the cache.
    /// Note: For PoolNonTv, sharesToken == baseToken.
    /// This fn is used by both retrieveBase() and retrieveShares().
    /// @param to Address of the recipient of the shares/base tokens.
    /// @return retrieved The amount of shares/base tokens sent.
    function _retrieveBase(address to) internal virtual returns (uint128 retrieved) {
        // For PoolNonTv, sharesToken == baseToken. This allows for the use of the core Pool.sol contract logic with
        // non-yield-bearing tokens. As such the sharesCached state var actually represents baseTokens, since they
        // are the same.
        retrieved = (sharesToken.balanceOf(address(this)) - sharesCached).u128();
        sharesToken.safeTransfer(to, retrieved);
    }

    /// **This function is intentionally empty to overwrite the Pool._approveSharesToken fn.**
    /// This is normally used by Pool.constructor give max approval to sharesToken, but not needed for Non-Tv pool.
    function _approveSharesToken(IERC20Like baseToken_, address sharesToken_) internal virtual override {}

    /// This is used by the constructor to set the base token as immutable.
    /// For Non-tokenized vaults, the base is the same as the base asset.
    function _getBaseAsset(address sharesToken_) internal virtual override returns (IERC20Like) {
        return IERC20Like(sharesToken_);
    }

    /// Returns the current price of one share.  For non-tokenized vaults this is always 1.
    /// This function should be overriden by modules.
    /// @return By always returning 1, we can use this module with any non-tokenized vault base such as WETH.
    function _getCurrentSharePrice() internal view virtual override returns (uint256) {
        return uint256(10**baseDecimals);
    }

    /// Internal function for wrapping base asset tokens.
    /// Since there is nothing to unwrap, we return the surplus balance.
    /// @return shares The amount of wrapped tokens that are sent to the receiver.
    function _wrap(address receiver) internal virtual override returns (uint256 shares) {
        shares = _getSharesBalance() - sharesCached;
        if (receiver != address(this)) {
            sharesToken.safeTransfer(receiver, shares);
        }
    }

    /// Internal function to preview how many shares will be received when depositing a given amount of assets.
    /// @param assets The amount of base asset tokens to preview the deposit.
    /// @return shares The amount of shares that would be returned from depositing.
    function _wrapPreview(uint256 assets) internal view virtual override returns (uint256 shares) {
        shares = assets;
    }

    /// Internal function for unwrapping unaccounted for base in this contract.
    /// Since there is nothing to unwrap, we return the surplus balance.
    /// @return assets The amount of base assets sent to the receiver.
    function _unwrap(address receiver) internal virtual override returns (uint256 assets) {
        assets = _getSharesBalance() - sharesCached;
        if (receiver != address(this)) {
            sharesToken.safeTransfer(receiver, assets);
        }
    }

    /// Internal function to preview how many asset tokens will be received when unwrapping a given amount of shares.
    /// @param shares The amount of shares to preview a redemption.
    /// @return assets The amount of base asset tokens that would be returned from redeeming.
    function _unwrapPreview(uint256 shares) internal view virtual override returns (uint256 assets) {
        assets = shares;
    }
}
