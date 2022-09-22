// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILadle.sol";
import "./ICauldron.sol";
import "./DataTypes.sol";

interface IWitch {
    /// @return The Cauldron the witch is using under-the-bonnet
    function cauldron() external view returns (ICauldron);

    /// @return The Ladle the witch is using under-the-bonnet
    function ladle() external view returns (ILadle);

    /// @dev Queries the ongoing auctions
    /// @param vaultId Id of the vault to query an auction for
    /// @return auction_ Info associated to the auction
    function auctions(bytes12 vaultId)
        external
        view
        returns (DataTypes.Auction memory auction_);

    /// @dev Queries the params that govern how time influences collateral price in auctions
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of asset used for underlying
    /// @return line Parameters that govern how much collateral is sold over time.
    function lines(bytes6 ilkId, bytes6 baseId)
        external
        view
        returns (DataTypes.Line memory line);

    /// @dev Queries the params that govern how much collateral of each kind can be sold at any given time.
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of asset used for underlying
    /// @return limits_ Parameters that govern how much collateral of each kind can be sold at any given time.
    function limits(bytes6 ilkId, bytes6 baseId)
        external
        view
        returns (DataTypes.Limits memory limits_);

    /// @dev Put an under-collateralised vault up for liquidation
    /// @param vaultId Id of the vault to liquidate
    /// @param to Receiver of the auctioneer reward
    /// @return auction_ Info related to the auction itself
    /// @return vault Vault that's being auctioned
    /// @return series Series for the vault that's being auctioned
    function auction(bytes12 vaultId, address to)
        external
        returns (
            DataTypes.Auction memory auction_,
            DataTypes.Vault memory vault,
            DataTypes.Series memory series
        );

    /// @dev Cancel an auction for a vault that isn't under-collateralised any more
    /// @param vaultId Id of the vault to remove from auction
    function cancel(bytes12 vaultId) external;

    /// @notice If too much base is offered, only the necessary amount are taken.
    /// @dev Pay at most `maxBaseIn` of the debt in a vault in liquidation, getting at least `minInkOut` collateral.
    /// @param vaultId Id of the vault to buy
    /// @param to Receiver of the collateral bought
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @param maxBaseIn Maximum amount of base that the liquidator will pay
    /// @return liquidatorCut Amount paid to `to`.
    /// @return auctioneerCut Amount paid to an address specified by whomever started the auction. 0 if it's the same as the `to` address
    /// @return baseIn Amount of underlying taken
    function payBase(
        bytes12 vaultId,
        address to,
        uint128 minInkOut,
        uint128 maxBaseIn
    )
        external
        returns (
            uint256 liquidatorCut,
            uint256 auctioneerCut,
            uint256 baseIn
        );

    /// @notice If too much fyToken are offered, only the necessary amount are taken.
    /// @dev Pay up to `maxArtIn` debt from a vault in liquidation using fyToken, getting at least `minInkOut` collateral.
    /// @param vaultId Id of the vault to buy
    /// @param to Receiver for the collateral bought
    /// @param maxArtIn Maximum amount of fyToken that will be paid
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @return liquidatorCut Amount paid to `to`.
    /// @return auctioneerCut Amount paid to an address specified by whomever started the auction. 0 if it's the same as the `to` address
    /// @return artIn Amount of fyToken taken
    function payFYToken(
        bytes12 vaultId,
        address to,
        uint128 minInkOut,
        uint128 maxArtIn
    )
        external
        returns (
            uint256 liquidatorCut,
            uint256 auctioneerCut,
            uint128 artIn
        );

    /*
          x x x
        x      x    Hi Fren!
       x  .  .  x   I want to buy this vault under auction!  I'll pay
       x        x   you in the same `base` currency of the debt, or in fyToken, but
       x        x   I want no less than `uint min` of the collateral, ok?
       x   ===  x
       x       x
         xxxxx
           x                             __  Ok Fren!
           x     ┌────────────┐  _(\    |@@|
           xxxxxx│ BASE BUCKS │ (__/\__ \--/ __
           x     │     OR     │    \___|----|  |   __
           x     │   FYTOKEN  │        \ }{ /\ )_ / _\
          x x    └────────────┘        /\__/\ \__O (__
                                      (--/\--)    \__/
                               │      _)(  )(_
                               │     `---''---`
                               ▼
         _______
        /  12   \  First lets check how much time `t` is left on the auction
       |    |    | because that helps us determine the price we will accept
       |9   |   3| for the debt! Yay!
       |     \   |                       p + (1 - p) * t
       |         |
        \___6___/          (p is the auction starting price!)
   
                               │
                               │
                               ▼                  (\
                                                   \ \
       Then the Cauldron updates our internal    __    \/ ___,.-------..__        __
       accounting by slurping up the debt      //\\ _,-'\\               `'--._ //\\
       and the collateral from the vault!      \\ ;'      \\                   `: //
                                                `(          \\                   )'
       The Join then dishes out the collateral    :.          \\,----,         ,;
       to you, dear user. And the debt is          `.`--.___   (    /  ___.--','
       settled with the base join or debt fyToken.   `.     ``-----'-''     ,'
                                                       -.               ,-
                                                          `-._______.-'
    */

    /// @dev quotes how much ink a liquidator is expected to get if it repays an `artIn` amount. Works for both Auctioned and ToBeAuctioned vaults
    /// @param vaultId The vault to get a quote for
    /// @param to Address that would get the collateral bought
    /// @param maxArtIn How much of the vault debt will be paid. GT than available art means all
    /// @return liquidatorCut How much collateral the liquidator is expected to get
    /// @return auctioneerCut How much collateral the auctioneer is expected to get. 0 if liquidator == auctioneer
    /// @return artIn How much debt the liquidator is expected to pay
    function calcPayout(
        bytes12 vaultId,
        address to,
        uint256 maxArtIn
    )
        external
        view
        returns (
            uint256 liquidatorCut,
            uint256 auctioneerCut,
            uint256 artIn
        );
}
