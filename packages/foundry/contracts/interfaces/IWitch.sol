// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILadle.sol";
import "./ICauldron.sol";
import "./DataTypes.sol";

interface IWitch {
    function cauldron() external returns (ICauldron);

    function ladle() external returns (ILadle);

    function auctions(bytes12) external returns (DataTypes.Auction memory);

    function lines(bytes6, bytes6) external returns (DataTypes.Line memory);

    function limits(bytes6, bytes6) external returns (DataTypes.Limits memory);

    /// @dev Put an undercollateralized vault up for liquidation
    /// @param vaultId Id of vault to liquidate
    /// @param to Receiver of the auctioneer reward
    function auction(bytes12 vaultId, address to)
        external
        returns (DataTypes.Auction memory);

    /// @dev Cancel an auction for a vault that isn't undercollateralized anymore
    /// @param vaultId Id of vault to return
    function cancel(bytes12 vaultId) external;

    /// @dev Pay at most `maxBaseIn` of the debt in a vault in liquidation, getting at least `minInkOut` collateral.
    /// @param vaultId Id of vault to buy
    /// @param to Receiver of the collateral bought
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @param maxBaseIn Maximum amount of base that the liquidator will pay
    /// @return inkOut Amount of vault collateral sold
    /// @return baseIn Amount of underlying taken
    function payBase(
        bytes12 vaultId,
        address to,
        uint128 minInkOut,
        uint128 maxBaseIn
    ) external returns (uint256 inkOut, uint256 baseIn);

    /// @dev Pay up to `maxArtIn` debt from a vault in liquidation using fyToken, getting at least `minInkOut` collateral.
    /// @notice If too much fyToken are offered, only the necessary amount are taken.
    /// @param vaultId Id of vault to buy
    /// @param to Receiver for the collateral bought
    /// @param maxArtIn Maximum amount of fyToken that will be paid
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @return inkOut Amount of vault collateral sold
    /// @return artIn Amount of fyToken taken
    function payFYToken(
        bytes12 vaultId,
        address to,
        uint128 minInkOut,
        uint128 maxArtIn
    ) external returns (uint256 inkOut, uint256 artIn);

    /*

        x x x
    x      x    Hi Fren!
    x  .  .  x   I want to buy this vault under auction!  I'll pay
    x        x   you in the same `base` currency of the debt, or in fyToken, but
    x        x   I want no less than `uint min` of the collateral, ok?
    x   ===  x
    x       x
        xxxxxxx
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
    The Join  then dishes out the collateral   :.          \\,----,         ,;
    to you, dear user. And the debt is          `.`--.___   (    /  ___.--','
    settled with the base join or debt fyToken.   `.     ``-----'-''     ,'
                                                    -.               ,-
                                                        `-._______.-'gpyy


    */
    /// @dev quoutes hoy much ink a liquidator is expected to get if it repays an `artIn` amount
    /// @param vaultId The vault to get a quote for
    /// @param artIn How much of the vault debt will be paid. 0 means all
    /// @return inkOut How much collateral the liquidator is expected to get
    function calcPayout(bytes12 vaultId, uint256 artIn)
        external
        view
        returns (uint256 inkOut);
}
