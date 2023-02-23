// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";
import "@yield-protocol/utils-v2/contracts/math/WDivUp.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./interfaces/ILadle.sol";
import "./interfaces/ICauldron.sol";
import "./interfaces/IJoin.sol";
import "./interfaces/DataTypes.sol";

library WitchLibrary {
    using WMul for uint256;
    using WDiv for uint256;
    using WDivUp for uint256;
    using CastU256U128 for uint256;
    
    uint128 public constant ONE_HUNDRED_PERCENT = 1e18;
    error JoinNotFound(bytes6 id);

    /// @dev transfers funds from the ilkJoin to the liquidator (and potentially the auctioneer if they're different people)
    /// @param ilkId The ilkId of the collateral
    /// @param to Who's gonna get the `liquidatorCut`
    /// @param auctioneer Who's gonna get the `auctioneerCut`
    /// @param liquidatorCut How much collateral the liquidator is expected to get
    /// @param auctioneerCut How much collateral the auctioneer is expected to get. 0 if liquidator == auctioneer
    /// @return updated liquidatorCut & auctioneerCut
    function _payInk(
        ILadle ladle,
        bytes6 ilkId,
        address auctioneer,
        address to,
        uint256 liquidatorCut,
        uint256 auctioneerCut
    ) internal returns (uint256, uint256) {
        IJoin ilkJoin = ladle.joins(ilkId);
        if (ilkJoin == IJoin(address(0))) {
            revert JoinNotFound(ilkId);
        }

        // Pay auctioneer's cut if necessary
        if (auctioneerCut > 0) {
            // A transfer revert would block the auction, in that case the liquidator gets the auctioneer's cut as well
            try ilkJoin.exit(auctioneer, auctioneerCut.u128()) returns (
                uint128
            ) {} catch {
                liquidatorCut += auctioneerCut;
                auctioneerCut = 0;
            }
        }

        // Give collateral to the liquidator
        if (liquidatorCut > 0) {
            ilkJoin.exit(to, liquidatorCut.u128());
        }

        return (liquidatorCut, auctioneerCut);
    }

    /// @notice Return how much collateral should be given out.
    /// @dev Calculate how much collateral to give for paying a certain amount of debt, at a certain time, for a certain vault.
    /// @param auction_ Auction data
    /// @param to Who's gonna get the collateral
    /// @param artIn How much debt is being repaid
    /// @return liquidatorCut how much collateral will be paid to `to`
    /// @return auctioneerCut how much collateral will be paid to whomever started the auction
    /// Formula: (artIn / totalArt) * totalInk * (initialProportion + (1 - initialProportion) * t)
    function _calcPayout(
        DataTypes.Auction memory auction_,
        DataTypes.Line memory line_,
        address to,
        uint256 artIn,
        uint256 auctioneerReward
    ) internal view returns (uint256 liquidatorCut, uint256 auctioneerCut) {
        uint256 duration = line_.duration;
        uint256 initialCollateralProportion = line_.collateralProportion;

        uint256 collateralProportionNow;
        uint256 elapsed = block.timestamp - auction_.start;
        if (duration == type(uint32).max) {
            // Interpreted as infinite duration
            collateralProportionNow = initialCollateralProportion;
        } else if (elapsed >= duration) {
            collateralProportionNow = ONE_HUNDRED_PERCENT;
        } else {
            collateralProportionNow =
                initialCollateralProportion +
                ((ONE_HUNDRED_PERCENT - initialCollateralProportion) *
                    elapsed) /
                duration;
        }

        uint256 inkAtEnd = artIn.wdiv(auction_.art).wmul(auction_.ink);
        liquidatorCut = inkAtEnd.wmul(collateralProportionNow);
        if (auction_.auctioneer != to) {
            auctioneerCut = liquidatorCut.wmul(auctioneerReward);
            liquidatorCut -= auctioneerCut;
        }
    }

    /// @dev Calculates the auction initial values, the 2 non-trivial values are how much art must be repaid
    /// and what's the max ink that will be offered in exchange. For the realtime amount of ink that's on offer
    /// use `_calcPayout`
    /// @param ilkId The ilkId of the collateral
    /// @param baseId The baseId of the collateral
    /// @param seriesId The seriesId of the collateral
    /// @param vaultOwner Who owns the vault
    /// @param to Who's gonna get the auctioneerCut
    /// @param balances Balances data
    /// @param debt Debt data
    /// @return auction_ Auction data
    /// @return line Line data
    function _calcAuction(
        bytes6 ilkId,
        bytes6 baseId,
        bytes6 seriesId,
        address vaultOwner,
        address to,
        DataTypes.Balances memory balances,
        DataTypes.Debt memory debt,
        DataTypes.Line memory line
    )
        internal
        view
        returns (DataTypes.Auction memory auction_, DataTypes.Line memory )
    {
        // We try to partially liquidate the vault if possible.
        
        uint256 vaultProportion = line.vaultProportion;

        // There's a min amount of debt that a vault can hold,
        // this limit is set so liquidations are big enough to be attractive,
        // so 2 things have to be true:
        //      a) what we are putting up for liquidation has to be over the min
        //      b) what we leave in the vault has to be over the min (or zero) in case another liquidation has to be performed
        uint256 min = debt.min * (10**debt.dec);

        uint256 art;
        uint256 ink;

        if (balances.art > min) {
            // We optimistically assume the vaultProportion to be liquidated is correct.
            art = uint256(balances.art).wmul(vaultProportion);

            // If the vaultProportion we'd be liquidating is too small
            if (art < min) {
                // We up the amount to the min
                art = min;
                // We calculate the new vaultProportion of the vault that we're liquidating
                vaultProportion = art.wdivup(balances.art);
            }

            // If the debt we'd be leaving in the vault is too small
            if (balances.art - art < min) {
                // We liquidate everything
                art = balances.art;
                // Proportion is set to 100%
                vaultProportion = ONE_HUNDRED_PERCENT;
            }

            // We calculate how much ink has to be put for sale based on how much art are we asking to be repaid
            ink = uint256(balances.ink).wmul(vaultProportion);
        } else {
            // If min debt was raised, any vault that's left below the new min should be liquidated 100%
            art = balances.art;
            ink = balances.ink;
        }

        auction_ = DataTypes.Auction({
            owner: vaultOwner,
            start: uint32(block.timestamp), // Overflow can't happen as max value is checked before
            seriesId: seriesId,
            baseId: baseId,
            ilkId: ilkId,
            art: art.u128(),
            ink: ink.u128(),
            auctioneer: to
        });
    }
}