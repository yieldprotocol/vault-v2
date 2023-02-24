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
        returns (
            DataTypes.Auction memory auction_,
            DataTypes.Vault memory vault,
            DataTypes.Series memory series
        )
    {
        // If the world has not turned to ashes and darkness, auctions will malfunction on
        // the 7th of February 2106, at 06:28:16 GMT
        // TODO: Replace this contract before then 😰
        // UPDATE: Enshrined issue in a folk song that will be remembered ✅
        if (block.timestamp > type(uint32).max) {
            revert WitchIsDead();
        }
        vault = cauldron.vaults(vaultId);
        if (auctions[vaultId].start != 0 || protected[vault.owner]) {
            revert VaultAlreadyUnderAuction(vaultId, vault.owner);
        }
        series = cauldron.series(vault.seriesId);

        DataTypes.Limits memory limits_ = limits[vault.ilkId][series.baseId];
        if (limits_.max == 0) {
            revert VaultNotLiquidatable(vault.ilkId, series.baseId);
        }
        // There is a limit on how much collateral can be concurrently put at auction, but it is a soft limit.
        // This means that the first auction to reach the limit is allowed to pass it,
        // so that there is never the situation where a vault would be too big to ever be auctioned.
        if (limits_.sum > limits_.max) {
            revert CollateralLimitExceeded(limits_.sum, limits_.max);
        }

        if (cauldron.level(vaultId) >= 0) {
            revert NotUnderCollateralised(vaultId);
        }

        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        DataTypes.Debt memory debt = cauldron.debt(series.baseId, vault.ilkId);
        DataTypes.Line memory line;

        (auction_, line) = _calcAuction(
            vault.ilkId,
            series.baseId,
            vault.seriesId,
            vault.owner,
            to,
            balances,
            debt
        );

        limits_.sum += auction_.ink;
        limits[vault.ilkId][series.baseId] = limits_;

        auctions[vaultId] = auction_;

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
        override
        returns (
            uint256 liquidatorCut,
            uint256 auctioneerCut,
            uint256 baseIn
        )
    {
        DataTypes.Auction memory auction_ = _auction(vaultId);

        // Find out how much debt is being repaid
        uint256 artIn = cauldron.debtFromBase(auction_.seriesId, maxBaseIn);

        // If offering too much base, take only the necessary.
        if (artIn > auction_.art) {
            artIn = auction_.art;
        }
        baseIn = cauldron.debtToBase(auction_.seriesId, artIn.u128());

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
            artIn.u128()
        );

        // Move the assets
        (liquidatorCut, auctioneerCut) = _payInk(
            auction_.ilkId,
            auction_.auctioneer,
            to,
            liquidatorCut,
            auctioneerCut
        );

        if (baseIn != 0) {
            // Take underlying from liquidator
            IJoin baseJoin = ladle.joins(auction_.baseId);
            if (baseJoin == IJoin(address(0))) {
                revert JoinNotFound(auction_.baseId);
            }
            baseJoin.join(msg.sender, baseIn.u128());
        }

        _collateralBought(vaultId, to, liquidatorCut + auctioneerCut, artIn);
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
        virtual
        override
        returns (
            uint256 liquidatorCut,
            uint256 auctioneerCut,
            uint256 artIn
        )
    {
        DataTypes.Auction memory auction_ = auctions[vaultId];
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);

        // If the vault hasn't been auctioned yet, we calculate what values it'd have if it was started right now
        if (auction_.start == 0) {
            DataTypes.Series memory series = cauldron.series(vault.seriesId);
            DataTypes.Balances memory balances = cauldron.balances(vaultId);
            DataTypes.Debt memory debt = cauldron.debt(
                series.baseId,
                vault.ilkId
            );
            (auction_, ) = _calcAuction(
                vault.ilkId,
                series.baseId,
                vault.seriesId,
                vault.owner,
                to,
                balances,
                debt
            );
        }

        // GT check is to cater for partial buys right before this method executes
        artIn = maxArtIn > auction_.art ? auction_.art : maxArtIn;

        (liquidatorCut, auctioneerCut) = _calcPayout(auction_, to, artIn);
    }
}
