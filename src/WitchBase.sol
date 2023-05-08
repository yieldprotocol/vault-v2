// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "./interfaces/DataTypes.sol";
import "./interfaces/ILadle.sol";
import "./interfaces/ICauldron.sol";
import "./interfaces/IJoin.sol";
import "./interfaces/IWitchEvents.sol";
import "./interfaces/IWitchErrors.sol";

contract WitchBase is AccessControl, IWitchEvents, IWitchErrors {
    using Math for uint256;
    using Cast for uint256;

    // ==================== Modifiers ====================

    modifier beforeAshes() {
        // If the world has not turned to ashes and darkness, auctions will malfunction on
        // the 7th of February 2106, at 06:28:16 GMT
        // TODO: Replace this contract before then 😰
        // UPDATE: Enshrined issue in a folk song that will be remembered ✅
        if (block.timestamp > type(uint32).max) {
            revert WitchIsDead();
        }
        _;
    }

    struct VaultBalanceDebtData {
        bytes6 ilkId;
        bytes6 baseId;
        bytes6 seriesId;
        address owner;
        DataTypes.Balances balances;
        DataTypes.Debt debt;
    }

    uint128 public constant ONE_HUNDRED_PERCENT = 1e18;
    uint128 public constant ONE_PERCENT = 0.01e18;

    // Reward given to whomever calls `auction`. It represents a % of the bought collateral
    uint256 public auctioneerReward;
    ILadle public ladle;
    ICauldron public immutable cauldron;

    mapping(bytes12 => DataTypes.Auction) public auctions;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Line)) public lines;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Limits)) public limits;
    mapping(address => bool) public protected;

    constructor(ICauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
        auctioneerReward = ONE_PERCENT;
    }

    // ======================================================================
    // =                        Governance functions                        =
    // ======================================================================

    /// @dev Point to a different ladle
    /// @param param Name of parameter to set (must be "ladle")
    /// @param value Address of new ladle
    function point(bytes32 param, address value) external auth {
        if (param != "ladle") {
            revert UnrecognisedParam(param);
        }
        address oldLadle = address(ladle);
        ladle = ILadle(value);
        emit Point(param, oldLadle, value);
    }

    /// @dev Governance function to set the parameters that govern how much collateral is sold over time.
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of asset used for underlying
    /// @param duration Time that auctions take to go to minimal price
    /// @param vaultProportion Vault proportion that is set for auction each time
    /// @param collateralProportion Proportion of collateral that is sold at auction start (1e18 = 100%)
    /// @param max Maximum concurrent auctioned collateral
    function setLineAndLimit(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 vaultProportion,
        uint64 collateralProportion,
        uint128 max
    ) external auth {
        require(
            collateralProportion <= ONE_HUNDRED_PERCENT,
            "Collateral Proportion above 100%"
        );
        require(
            vaultProportion <= ONE_HUNDRED_PERCENT,
            "Vault Proportion above 100%"
        );
        require(
            collateralProportion >= ONE_PERCENT,
            "Collateral Proportion below 1%"
        );
        require(vaultProportion >= ONE_PERCENT, "Vault Proportion below 1%");

        lines[ilkId][baseId] = DataTypes.Line({
            duration: duration,
            vaultProportion: vaultProportion,
            collateralProportion: collateralProportion
        });
        emit LineSet(
            ilkId,
            baseId,
            duration,
            vaultProportion,
            collateralProportion
        );

        limits[ilkId][baseId] = DataTypes.Limits({
            max: max,
            sum: limits[ilkId][baseId].sum // sum is initialized at zero, and doesn't change when changing any ilk parameters
        });
        emit LimitSet(ilkId, baseId, max);
    }

    /// @dev Governance function to protect specific vault owners from liquidations.
    /// @param owner The address that may be set/unset as protected
    /// @param _protected Is this address protected or not
    function setProtected(address owner, bool _protected) external auth {
        protected[owner] = _protected;
        emit ProtectedSet(owner, _protected);
    }

    /// @dev Governance function to set the % paid to whomever starts an auction
    /// @param auctioneerReward_ New % to be used, must have 18 dec precision
    function setAuctioneerReward(uint256 auctioneerReward_) external auth {
        if (auctioneerReward_ > ONE_HUNDRED_PERCENT) {
            revert AuctioneerRewardTooHigh(
                ONE_HUNDRED_PERCENT,
                auctioneerReward_
            );
        }
        auctioneerReward = auctioneerReward_;
        emit AuctioneerRewardSet(auctioneerReward_);
    }

    // ======================================================================
    // =                    Auction management functions                    =
    // ======================================================================

    /// @dev Checks whether vault is eligible for auction and calculates auction parameters.
    /// @param vaultId Id of vault to be auctioned
    /// @param baseId Id of asset used for underlying
    /// @param ilkId Id of asset used for collateral
    /// @param seriesId Id of series used for debt
    /// @param vaultOwner Owner of the vault to be auctioned
    /// @param to Address that will receive the bought collateral
    function _calcAuctionParameters(
        bytes12 vaultId,
        bytes6 baseId,
        bytes6 ilkId,
        bytes6 seriesId,
        address vaultOwner,
        address to
    )
        internal
        returns (DataTypes.Auction memory auction_, DataTypes.Line memory line)
    {
        if (auctions[vaultId].start != 0 || protected[vaultOwner]) {
            revert VaultAlreadyUnderAuction(vaultId, vaultOwner);
        }

        DataTypes.Limits memory limits_ = limits[ilkId][baseId];
        if (limits_.max == 0) {
            revert VaultNotLiquidatable(ilkId, baseId);
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
        DataTypes.Debt memory debt = cauldron.debt(baseId, ilkId);

        (auction_, line) = _calcAuction(
            ilkId,
            baseId,
            seriesId,
            vaultOwner,
            to,
            balances,
            debt
        );

        limits_.sum += auction_.ink;
        limits[ilkId][baseId] = limits_;

        auctions[vaultId] = auction_;
    }

    /// @dev Cancel an auction for a vault that isn't under-collateralised any more
    /// @param vaultId Id of the vault to remove from auction
    function cancel(bytes12 vaultId) external {
        DataTypes.Auction memory auction_ = _auction(vaultId);
        if (cauldron.level(vaultId) < 0) {
            revert UnderCollateralised(vaultId);
        }

        // Update concurrent collateral under auction
        limits[auction_.ilkId][auction_.baseId].sum -= auction_.ink;

        _auctionEnded(vaultId, auction_.owner);

        emit Cancelled(vaultId);
    }

    /// @dev Moves the vault ownership back to the original owner & clean internal state.
    /// Useful as a method so it can be overridden by specialised witches that may need to do extra accounting or notify 3rd parties
    /// @param vaultId Id of the liquidated vault
    function _auctionEnded(bytes12 vaultId, address owner) internal virtual {
        cauldron.give(vaultId, owner);
        delete auctions[vaultId];
        emit Ended(vaultId);
    }

    /// @dev Remove an auction for a vault that isn't owned by this Witch
    /// @notice Other witches or similar contracts can take vaults
    /// @param vaultId Id of the vault whose auction we will clear
    function clear(bytes12 vaultId) external {
        DataTypes.Auction memory auction_ = _auction(vaultId);
        if (cauldron.vaults(vaultId).owner == address(this)) {
            revert AuctionIsCorrect(vaultId);
        }

        // Update concurrent collateral under auction
        limits[auction_.ilkId][auction_.baseId].sum -= auction_.ink;
        delete auctions[vaultId];
        emit Cleared(vaultId);
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
        DataTypes.Debt memory debt
    )
        internal
        view
        returns (DataTypes.Auction memory auction_, DataTypes.Line memory line)
    {
        // We try to partially liquidate the vault if possible.
        line = lines[ilkId][baseId];
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
        returns (
            uint256 liquidatorCut,
            uint256 auctioneerCut,
            uint256 baseIn
        )
    {
        DataTypes.Auction memory auction_ = _auction(vaultId);

        // Find out how much debt is being repaid
        uint256 artIn = _debtFromBase(auction_, maxBaseIn);

        // If offering too much base, take only the necessary.
        if (artIn > auction_.art) {
            artIn = auction_.art;
        }
        baseIn = _debtToBase(auction_, artIn.u128());

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

    /// @notice Returns debt that could be paid given the maxBaseIn
    function _debtFromBase(DataTypes.Auction memory auction_, uint128 maxBaseIn)
        internal
        virtual
        returns (uint256 artIn)
    {}

    /// @notice Returns base that could be paid given the artIn
    function _debtToBase(DataTypes.Auction memory auction_, uint128 artIn)
        internal
        virtual
        returns (uint256 baseIn)
    {}

    /// @dev transfers funds from the ilkJoin to the liquidator (and potentially the auctioneer if they're different people)
    /// @param ilkId The ilkId of the collateral
    /// @param to Who's gonna get the `liquidatorCut`
    /// @param auctioneer Who's gonna get the `auctioneerCut`
    /// @param liquidatorCut How much collateral the liquidator is expected to get
    /// @param auctioneerCut How much collateral the auctioneer is expected to get. 0 if liquidator == auctioneer
    /// @return updated liquidatorCut & auctioneerCut
    function _payInk(
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

    /// @notice Update accounting on the Witch and on the Cauldron. Delete the auction and give back the vault if finished.
    /// @param vaultId Id of the liquidated vault
    /// @param auction_ Auction data
    /// @param inkOut How much collateral was sold
    /// @param artIn How much debt was repaid
    /// This function doesn't verify the vaultId matches the vault and auction passed. Check before calling.
    function _updateAccounting(
        bytes12 vaultId,
        DataTypes.Auction memory auction_,
        uint128 inkOut,
        uint128 artIn
    ) internal {
        // Duplicate check, but guarantees data integrity
        if (auction_.start == 0) {
            revert VaultNotUnderAuction(vaultId);
        }

        DataTypes.Limits memory limits_ = limits[auction_.ilkId][
            auction_.baseId
        ];

        // Update local auction
        {
            if (auction_.art == artIn) {
                // If there is no debt left, return the vault with the collateral to the owner
                _auctionEnded(vaultId, auction_.owner);

                // Update limits - reduce it by the whole auction
                limits_.sum -= auction_.ink;
            } else {
                // Ensure enough dust is left
                DataTypes.Debt memory debt = cauldron.debt(
                    auction_.baseId,
                    auction_.ilkId
                );

                uint256 remainder = auction_.art - artIn;
                uint256 min = debt.min * (10**debt.dec);
                if (remainder < min) {
                    revert LeavesDust(remainder, min);
                }

                // Update the auction
                auction_.ink -= inkOut;
                auction_.art -= artIn;

                // Store auction changes
                auctions[vaultId] = auction_;

                // Update limits - reduce it by whatever was bought
                limits_.sum -= inkOut;
            }
        }

        // Store limit changes
        limits[auction_.ilkId][auction_.baseId] = limits_;

        // Update accounting at Cauldron
        cauldron.slurp(vaultId, inkOut, artIn);
    }

    /// @dev Logs that a certain amount of a vault was liquidated
    /// Useful as a method so it can be overridden by specialised witches that may need to do extra accounting or notify 3rd parties
    /// @param vaultId Id of the liquidated vault
    /// @param buyer Who liquidated the vault
    /// @param ink How much collateral was sold
    /// @param art How much debt was repaid
    function _collateralBought(
        bytes12 vaultId,
        address buyer,
        uint256 ink,
        uint256 art
    ) internal virtual {
        emit Bought(vaultId, buyer, ink, art);
    }

    // ======================================================================
    // =                         Quoting functions                          =
    // ======================================================================

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

    function calcPayout(
        bytes12 vaultId,
        address to,
        uint256 maxArtIn
    )
        external
        view
        virtual
        returns (
            uint256 liquidatorCut,
            uint256 auctioneerCut,
            uint256 artIn
        )
    {
        DataTypes.Auction memory auction_ = auctions[vaultId];

        // If the vault hasn't been auctioned yet, we calculate what values it'd have if it was started right now
        if (auction_.start == 0) {
            VaultBalanceDebtData memory details = _getVaultDetailsAndDebt(
                vaultId
            );

            (auction_, ) = _calcAuction(
                details.ilkId,
                details.baseId,
                details.seriesId,
                details.owner,
                to,
                details.balances,
                details.debt
            );
        }

        // GT check is to cater for partial buys right before this method executes
        artIn = maxArtIn > auction_.art ? auction_.art : maxArtIn;

        (liquidatorCut, auctioneerCut) = _calcPayout(auction_, to, artIn);
    }

    function _getVaultDetailsAndDebt(bytes12 vaultId)
        internal
        view
        virtual
        returns (VaultBalanceDebtData memory)
    {}

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
        address to,
        uint256 artIn
    ) internal view returns (uint256 liquidatorCut, uint256 auctioneerCut) {
        DataTypes.Line memory line_ = lines[auction_.ilkId][auction_.baseId];
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

    /// @dev Loads the auction data for a given `vaultId` (if valid)
    /// @param vaultId Id of the vault for which we need the auction data
    /// @return auction_ Auction data for `vaultId`
    function _auction(bytes12 vaultId)
        internal
        view
        returns (DataTypes.Auction memory auction_)
    {
        auction_ = auctions[vaultId];

        if (auction_.start == 0) {
            revert VaultNotUnderAuction(vaultId);
        }
    }
}
