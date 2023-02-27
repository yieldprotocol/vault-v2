// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./WitchBase.sol";

/// @title  The Witch is a DataTypes.Auction/Liquidation Engine for the Yield protocol
/// @notice The Witch grabs under-collateralised vaults, replacing the owner by itself. Then it sells
/// the vault collateral in exchange for underlying to pay its debt. The amount of collateral
/// given increases over time, until it offers to sell all the collateral for underlying to pay
/// all the debt. The auction is held open at the final price indefinitely.
/// @dev After the debt is settled, the Witch returns the vault to its original owner.
contract Witch is WitchBase {
    using CastU256U128 for uint256;

    constructor(ICauldron cauldron_, ILadle ladle_)
        WitchBase(cauldron_, ladle_)
    {}

    // ======================================================================
    // =                    Auction management functions                    =
    // ======================================================================

    /// @dev Put an under-collateralised vault up for liquidation
    /// @param vaultId Id of the vault to liquidate
    /// @param to Receiver of the auctioneer reward
    /// @return auction_ Info associated to the auction itself
    /// @return vault Vault that's being auctioned
    /// @return series Series for the vault that's being auctioned
    function auction(bytes12 vaultId, address to)
        external
        beforeAshes
        returns (
            DataTypes.Auction memory auction_,
            DataTypes.Vault memory vault,
            DataTypes.Series memory series
        )
    {
        vault = cauldron.vaults(vaultId);
        series = cauldron.series(vault.seriesId);

        DataTypes.Line memory line;
        (auction_, line) = _calcAuctionParameters(
            vaultId,
            series.baseId,
            vault.ilkId,
            vault.seriesId,
            vault.owner,
            to
        );

        vault = _auctionStarted(vaultId, auction_, line);
    }

    /// @dev Moves the vault ownership to the witch.
    /// Useful as a method so it can be overridden by specialised witches that may need to do extra accounting or notify 3rd parties
    /// @param vaultId Id of the vault to liquidate
    function _auctionStarted(
        bytes12 vaultId,
        DataTypes.Auction memory auction_,
        DataTypes.Line memory line
    ) internal virtual returns (DataTypes.Vault memory vault) {
        // The Witch is now in control of the vault under auction
        vault = cauldron.give(vaultId, address(this));
        emit Auctioned(
            vaultId,
            auction_,
            line.duration,
            line.collateralProportion
        );
    }

    // ======================================================================
    // =                          Bidding functions                         =
    // ======================================================================

    /// @notice Returns debt that could be paid given the maxBaseIn
    function _debtFromBase(DataTypes.Auction memory auction_, uint128 maxBaseIn)
        internal
        virtual
        override
        returns (uint256 artIn)
    {
        artIn = cauldron.debtFromBase(auction_.seriesId, maxBaseIn);
    }

    /// @notice Returns base that could be paid given the artIn
    function _debtToBase(DataTypes.Auction memory auction_, uint128 artIn)
        internal
        virtual
        override
        returns (uint256 baseIn)
    {
        baseIn = cauldron.debtToBase(auction_.seriesId, artIn);
    }

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
        )
    {
        DataTypes.Auction memory auction_ = _auction(vaultId);

        // If offering too much fyToken, take only the necessary.
        artIn = maxArtIn > auction_.art ? auction_.art : maxArtIn;

        // Calculate the collateral to be sold
        (liquidatorCut, auctioneerCut) = _calcPayout(auction_, to, artIn);
        if (liquidatorCut < minInkOut) {
            revert NotEnoughBought(minInkOut, liquidatorCut);
        }

        // Update Cauldron and local auction data
        _updateAccounting(
            vaultId,
            auction_,
            (liquidatorCut + auctioneerCut).u128(),
            artIn
        );

        // Move the assets
        (liquidatorCut, auctioneerCut) = _payInk(
            auction_.ilkId,
            auction_.auctioneer,
            to,
            liquidatorCut,
            auctioneerCut
        );

        if (artIn != 0) {
            // Burn fyToken from liquidator
            cauldron.series(auction_.seriesId).fyToken.burn(msg.sender, artIn);
        }

        _collateralBought(vaultId, to, liquidatorCut + auctioneerCut, artIn);
    }

    // ======================================================================
    // =                         Quoting functions                          =
    // ======================================================================

    function _getVaultDetailsAndDebt(bytes12 vaultId)
        internal
        view
        override
        returns (
            bytes6 baseId,
            bytes6 ilkId,
            bytes6 seriesId,
            address owner,
            DataTypes.Debt memory debt
        )
    {
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        DataTypes.Series memory series = cauldron.series(vault.seriesId);
        debt = cauldron.debt(series.baseId, vault.ilkId);
        return (series.baseId, vault.ilkId, vault.seriesId, vault.owner, debt);
    }
}
