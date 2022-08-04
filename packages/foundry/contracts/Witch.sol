// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";
import "@yield-protocol/utils-v2/contracts/math/WDivUp.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./interfaces/ILadle.sol";
import "./interfaces/ICauldron.sol";
import "./interfaces/IJoin.sol";
import "./interfaces/DataTypes.sol";

/// @title  The Witch is a DataTypes.Auction/Liquidation Engine for the Yield protocol
/// @notice The Witch grabs under-collateralised vaults, replacing the owner by itself. Then it sells
/// the vault collateral in exchange for underlying to pay its debt. The amount of collateral
/// given increases over time, until it offers to sell all the collateral for underlying to pay
/// all the debt. The auction is held open at the final price indefinitely.
/// @dev After the debt is settled, the Witch returns the vault to its original owner.
contract Witch is AccessControl {
    using WMul for uint256;
    using WDiv for uint256;
    using WDivUp for uint256;
    using CastU256U128 for uint256;

    // ==================== Errors ====================

    error VaultAlreadyUnderAuction(bytes12 vaultId, address witch);
    error VaultNotLiquidatable(bytes6 ilkId, bytes6 baseId);
    error AuctioneerRewardTooHigh(uint256 max, uint256 actual);
    error WitchIsDead();
    error CollateralLimitExceeded(uint256 current, uint256 max);
    error NotUnderCollateralised(bytes12 vaultId);
    error UnderCollateralised(bytes12 vaultId);
    error VaultNotUnderAuction(bytes12 vaultId);
    error NotEnoughBought(uint256 expected, uint256 got);
    error JoinNotFound(bytes6 id);
    error UnrecognisedParam(bytes32 param);
    error LeavesDust(uint256 remainder, uint256 min);

    // ==================== User events ====================

    event Auctioned(
        bytes12 indexed vaultId,
        DataTypes.Auction auction,
        uint256 duration,
        uint256 initialCollateralProportion
    );
    event Cancelled(bytes12 indexed vaultId);
    event Ended(bytes12 indexed vaultId);
    event Bought(
        bytes12 indexed vaultId,
        address indexed buyer,
        uint256 ink,
        uint256 art
    );

    // ==================== Governance events ====================

    event Point(
        bytes32 indexed param,
        address indexed oldValue,
        address indexed newValue
    );
    event LineSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint32 duration,
        uint64 vaultProportion,
        uint64 collateralProportion
    );
    event LimitSet(bytes6 indexed ilkId, bytes6 indexed baseId, uint128 max);
    event AnotherWitchSet(address indexed value, bool isWitch);
    event AuctioneerRewardSet(uint256 auctioneerReward);

    ICauldron public immutable cauldron;
    ILadle public ladle;

    uint128 public constant ONE_HUNDRED_PERCENT = 1e18;
    uint128 public constant ONE_PERCENT = 0.01e18;

    // Reward given to whomever calls `auction`. It represents a % of the bought collateral
    uint256 public auctioneerReward;

    mapping(bytes12 => DataTypes.Auction) public auctions;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Line)) public lines;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Limits)) public limits;
    mapping(address => bool) public isWitch;

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

    /// @dev Governance function to set other liquidation contracts that may have taken vaults already.
    /// @param value The address that may be set/unset as another witch
    /// @param _isWitch Is this address a witch or not
    function setAnotherWitch(address value, bool _isWitch) external auth {
        isWitch[value] = _isWitch;
        emit AnotherWitchSet(value, _isWitch);
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
        if (auctions[vaultId].start != 0 || isWitch[vault.owner]) {
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

        (auction_, line) = _calcAuction(vault, series, to, balances, debt);

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

    /// @dev Calculates the auction initial values, the 2 non-trivial values are how much art must be repaid
    /// and what's the max ink that will be offered in exchange. For the realtime amount of ink that's on offer
    /// use `_calcPayout`
    /// @param vault Vault data
    /// @param series Series data
    /// @param to Who's gonna get the auctioneerCut
    /// @param balances Balances data
    /// @param debt Debt data
    /// @return auction_ Auction data
    /// @return line Line data
    function _calcAuction(
        DataTypes.Vault memory vault,
        DataTypes.Series memory series,
        address to,
        DataTypes.Balances memory balances,
        DataTypes.Debt memory debt
    )
        internal
        view
        returns (DataTypes.Auction memory auction_, DataTypes.Line memory line)
    {
        // We try to partially liquidate the vault if possible.
        line = lines[vault.ilkId][series.baseId];
        uint256 vaultProportion = line.vaultProportion;

        // There's a min amount of debt that a vault can hold,
        // this limit is set so liquidations are big enough to be attractive,
        // so 2 things have to be true:
        //      a) what we are putting up for liquidation has to be over the min
        //      b) what we leave in the vault has to be over the min (or zero) in case another liquidation has to be performed
        uint256 min = debt.min * (10**debt.dec);

        // We optimistically assume the vaultProportion to be liquidated is correct.
        uint256 art = uint256(balances.art).wmul(vaultProportion);

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
        uint256 ink = uint256(balances.ink).wmul(vaultProportion);

        auction_ = DataTypes.Auction({
            owner: vault.owner,
            start: uint32(block.timestamp), // Overflow can't happen as max value is checked before
            seriesId: vault.seriesId,
            baseId: series.baseId,
            ilkId: vault.ilkId,
            art: art.u128(),
            ink: ink.u128(),
            auctioneer: to
        });
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
            auction_,
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
            auction_,
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

    /// @dev transfers funds from the ilkJoin to the liquidator (and potentially the auctioneer if they're different people)
    /// @param auction_ Auction data
    /// @param to Who's gonna get the `liquidatorCut`
    /// @param liquidatorCut How much collateral the liquidator is expected to get
    /// @param auctioneerCut How much collateral the auctioneer is expected to get. 0 if liquidator == auctioneer
    /// @return updated liquidatorCut & auctioneerCut
    function _payInk(
        DataTypes.Auction memory auction_,
        address to,
        uint256 liquidatorCut,
        uint256 auctioneerCut
    ) internal returns (uint256, uint256) {
        IJoin ilkJoin = ladle.joins(auction_.ilkId);
        if (ilkJoin == IJoin(address(0))) {
            revert JoinNotFound(auction_.ilkId);
        }

        // Pay auctioneer's cut if necessary
        if (auctioneerCut > 0) {
            // A transfer revert would block the auction, in that case the liquidator gets the auctioneer's cut as well
            try
                ilkJoin.exit(auction_.auctioneer, auctioneerCut.u128())
            returns (uint128) {} catch {
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
            (auction_, ) = _calcAuction(vault, series, to, balances, debt);
        }

        // GT check is to cater for partial buys right before this method executes
        artIn = maxArtIn > auction_.art ? auction_.art : maxArtIn;

        (liquidatorCut, auctioneerCut) = _calcPayout(auction_, to, artIn);
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
