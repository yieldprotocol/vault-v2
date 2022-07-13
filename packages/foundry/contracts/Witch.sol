// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

/// @title  The Witch is a DataTypes.Auction/Liquidation Engine for the Yield protocol
/// @notice The Witch grabs uncollateralized vaults, replacing the owner by itself. Then it sells
/// the vault collateral in exchange for underlying to pay its debt. The amount of collateral
/// given increases over time, until it offers to sell all the collateral for underlying to pay
/// all the debt. The auction is held open at the final price indefinitely.
/// @dev After the debt is settled, the Witch returns the vault to its original owner.
contract Witch is AccessControl {
    using WMul for uint256;
    using WDiv for uint256;
    using CastU256U128 for uint256;

    // ==================== User events ====================

    error VaultAlreadyUnderAuction(bytes12 vaultId, address witch);
    error VaultNotLiquidable(bytes12 vaultId, bytes6 ilkId, bytes6 baseId);
    error AuctioneerRewardTooHigh(uint128 max, uint128 actual);

    event Auctioned(bytes12 indexed vaultId, uint256 indexed start);
    event Cancelled(bytes12 indexed vaultId);
    event Ended(bytes12 indexed vaultId);
    event Bought(
        bytes12 indexed vaultId,
        address indexed buyer,
        uint256 ink,
        uint256 art
    );

    // ==================== Governance events ====================

    event Point(bytes32 indexed param, address indexed value);
    event LineSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint32 duration,
        uint64 proportion,
        uint64 initialOffer
    );
    event LimitSet(bytes6 indexed ilkId, bytes6 indexed baseId, uint128 max);
    event AnotherWitchSet(address indexed value, bool isWitch);
    event IgnoredPairSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        bool ignore
    );
    event AuctioneerRewardSet(uint128 auctioneerReward);

    ICauldron public immutable cauldron;
    ILadle public ladle;

    // Reward given to whomever calls `auction`. It represents a % of the bought collateral
    uint128 public auctioneerReward = 0.01e18;

    mapping(bytes12 => DataTypes.Auction) public auctions;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Line)) public lines;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Limits)) public limits;
    mapping(address => bool) public otherWitches;
    mapping(bytes6 => mapping(bytes6 => bool)) public ignoredPairs;

    constructor(ICauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

    // ======================================================================
    // =                        Governance functions                        =
    // ======================================================================

    /// @dev Point to a different ladle
    /// @param param Name of parameter to set (must be "ladle")
    /// @param value Address of new ladle
    function point(bytes32 param, address value) external auth {
        require(param == "ladle", "Unrecognized");
        ladle = ILadle(value);
        emit Point(param, value);
    }

    /// @dev Governance function to set the parameters that govern how much collateral is sold over time.
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of asset used for underlying
    /// @param duration Time that auctions take to go to minimal price
    /// @param proportion Vault proportion that is set for auction each time
    /// @param initialOffer Proportion of collateral that is sold at auction start (1e18 = 100%)
    function setLine(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 proportion,
        uint64 initialOffer
    ) external auth {
        require(initialOffer <= 1e18, "InitialOffer above 100%");
        require(proportion <= 1e18, "Proportion above 100%");
        require(
            initialOffer == 0 || initialOffer >= 0.01e18,
            "InitialOffer below 1%"
        );
        require(proportion >= 0.01e18, "Proportion below 1%");
        lines[ilkId][baseId] = DataTypes.Line({
            duration: duration,
            proportion: proportion,
            initialOffer: initialOffer
        });
        emit LineSet(ilkId, baseId, duration, proportion, initialOffer);
    }

    /// @dev Governance function to set auction limits.
    ///  - the auction duration to calculate liquidation prices
    ///  - the proportion of the collateral that will be sold at auction start
    ///  - the maximum collateral that can be auctioned at the same time
    ///  - the minimum collateral that must be left when buying, unless buying all
    ///  - The decimals for maximum and minimum
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of asset used for underlying
    /// @param max Maximum concurrent auctioned collateral
    function setLimit(
        bytes6 ilkId,
        bytes6 baseId,
        uint128 max
    ) external auth {
        limits[ilkId][baseId] = DataTypes.Limits({
            max: max,
            sum: limits[ilkId][baseId].sum // sum is initialized at zero, and doesn't change when changing any ilk parameters
        });
        emit LimitSet(ilkId, baseId, max);
    }

    /// @dev Governance function to set other liquidation contracts that may have taken vaults already.
    /// @param value The address that may be set/unset as another witch
    /// @param isWitch Is this address a witch or not
    function setAnotherWitch(address value, bool isWitch) external auth {
        otherWitches[value] = isWitch;
        emit AnotherWitchSet(value, isWitch);
    }

    /// @dev Governance function to ignore pairs that can't be liquidated
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of asset used for underlying
    /// @param ignore Should this pair be ignored for liquidation
    function setIgnoredPair(
        bytes6 ilkId,
        bytes6 baseId,
        bool ignore
    ) external auth {
        ignoredPairs[ilkId][baseId] = ignore;
        emit IgnoredPairSet(ilkId, baseId, ignore);
    }

    /// @dev Governance function to set the % paid to whomever starts an auction
    /// @param auctioneerReward_ New % to be used, must have 18 dec precision
    function setAuctioneerReward(uint128 auctioneerReward_) external auth {
        if (auctioneerReward_ > 1e18) {
            revert AuctioneerRewardTooHigh(1e18, auctioneerReward_);
        }
        auctioneerReward = auctioneerReward_;
        emit AuctioneerRewardSet(auctioneerReward_);
    }

    // ======================================================================
    // =                    Auction management functions                    =
    // ======================================================================

    /// @dev Put an undercollateralized vault up for liquidation
    /// @param vaultId Id of vault to liquidate
    /// @param to Receiver of the auctioneer reward
    function auction(bytes12 vaultId, address to)
        external
        returns (DataTypes.Auction memory auction_)
    {
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        if (vault.owner == address(this) || otherWitches[vault.owner]) {
            revert VaultAlreadyUnderAuction(vaultId, vault.owner);
        }
        DataTypes.Series memory series = cauldron.series(vault.seriesId);
        if (ignoredPairs[vault.ilkId][series.baseId]) {
            revert VaultNotLiquidable(vaultId, vault.ilkId, series.baseId);
        }

        require(cauldron.level(vaultId) < 0, "Not undercollateralized");

        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        DataTypes.Debt memory debt = cauldron.debt(series.baseId, vault.ilkId);

        // There is a limit on how much collateral can be concurrently put at auction, but it is a soft limit.
        // If the limit has been surpassed, no more vaults of that collateral can be put for auction.
        // This avoids the scenario where some vaults might be too large to be auctioned.
        DataTypes.Limits memory limits_ = limits[vault.ilkId][
            series.baseId
        ];
        require(limits_.sum <= limits_.max, "Collateral limit reached");

        auction_ = _calcAuction(vault, series, to, balances, debt);

        limits_.sum += auction_.ink;
        limits[vault.ilkId][series.baseId] = limits_;

        auctions[vaultId] = auction_;

        _auctionStarted(vaultId);
    }

    /// @dev Moves the vault ownership to the witch.
    /// Useful as a method so it can be overriden by specialised witches that may need to do extra accounting or notify 3rd parties
    function _auctionStarted(bytes12 vaultId) internal virtual {
        // The Witch is now in control of the vault under auction
        cauldron.give(vaultId, address(this));
        emit Auctioned(vaultId, uint32(block.timestamp));
    }

    /// @dev Calculates the auction initial values, the 2 non-trivial values are how much art must be repayed
    /// and what's the max ink that will be offered in exchange. For the realtime amount of ink that's on offer
    /// use `_calcPayout`
    function _calcAuction(
        DataTypes.Vault memory vault,
        DataTypes.Series memory series,
        address to,
        DataTypes.Balances memory balances,
        DataTypes.Debt memory debt
    ) internal view returns (DataTypes.Auction memory) {
        // We store the proportion of the vault to auction, which is the whole vault if the debt would be below dust.
        DataTypes.Line storage line = lines[vault.ilkId][series.baseId];
        uint128 art = uint256(balances.art).wmul(line.proportion).u128();
        if (art < debt.min * (10**debt.dec)) art = balances.art;
        uint128 ink = (art == balances.art)
            ? balances.ink
            : uint256(balances.ink).wmul(line.proportion).u128();

        return
            DataTypes.Auction({
                owner: vault.owner,
                start: uint32(block.timestamp), // Overflow is fine
                seriesId: vault.seriesId,
                baseId: series.baseId,
                ilkId: vault.ilkId,
                art: art,
                ink: ink,
                auctioneer: to
            });
    }

    /// @dev Cancel an auction for a vault that isn't undercollateralized anymore
    /// @param vaultId Id of vault to return
    function cancel(bytes12 vaultId) external {
        DataTypes.Auction storage auction_ = auctions[vaultId];
        require(auction_.start > 0, "Vault not under auction");
        require(cauldron.level(vaultId) >= 0, "Undercollateralized");

        // Update concurrent collateral under auction
        limits[auction_.ilkId][auction_.baseId].sum -= auction_.ink;

        _auctionEnded(vaultId, auction_.owner);

        emit Cancelled(vaultId);
    }

    /// @dev Moves the vault ownership back to the original owner & clean internal state.
    /// Useful as a method so it can be overriden by specialised witches that may need to do extra accounting or notify 3rd parties
    function _auctionEnded(bytes12 vaultId, address owner) internal virtual {
        cauldron.give(vaultId, owner);
        delete auctions[vaultId];
        emit Ended(vaultId);
    }

    // ======================================================================
    // =                          Bidding functions                         =
    // ======================================================================

    /// @dev Pay at most `maxBaseIn` of the debt in a vault in liquidation, getting at least `minInkOut` collateral.
    /// @param vaultId Id of vault to buy
    /// @param to Receiver of the collateral bought
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @param maxBaseIn Maximum amount of base that the liquidator will pay
    /// @return liquidatorCut Amount paid to `to`.
    /// @return auctioneerCut Amount paid to whomever started the auction. 0 if it's the same address that's calling this method
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
        DataTypes.Auction memory auction_ = auctions[vaultId];
        require(auction_.start > 0, "Vault not under auction");

        // Find out how much debt is being repaid
        uint128 artIn = uint128(
            cauldron.debtFromBase(auction_.seriesId, maxBaseIn)
        );

        // If offering too much base, take only the necessary.
        artIn = artIn > auction_.art ? auction_.art : artIn;
        baseIn = cauldron.debtToBase(auction_.seriesId, artIn);

        // Calculate the collateral to be sold
        (liquidatorCut, auctioneerCut) = _calcPayout(auction_, to, artIn);
        require(liquidatorCut >= minInkOut, "Not enough bought");

        // Update Cauldron and local auction data
        _updateAccounting(
            vaultId,
            auction_,
            liquidatorCut + auctioneerCut,
            artIn
        );

        // Move the assets
        _payInk(auction_, to, liquidatorCut, auctioneerCut);
        if (baseIn != 0) {
            // Take underlying from liquidator
            IJoin baseJoin = ladle.joins(auction_.baseId);
            require(baseJoin != IJoin(address(0)), "Join not found");
            baseJoin.join(msg.sender, baseIn.u128());
        }

        _collateralBought(vaultId, to, liquidatorCut + auctioneerCut, artIn);
    }

    /// @dev Pay up to `maxArtIn` debt from a vault in liquidation using fyToken, getting at least `minInkOut` collateral.
    /// @notice If too much fyToken are offered, only the necessary amount are taken.
    /// @param vaultId Id of vault to buy
    /// @param to Receiver for the collateral bought
    /// @param maxArtIn Maximum amount of fyToken that will be paid
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @return liquidatorCut Amount paid to `to`.
    /// @return auctioneerCut Amount paid to whomever started the auction. 0 if it's the same address that's calling this method
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
            uint256 artIn
        )
    {
        DataTypes.Auction memory auction_ = auctions[vaultId];
        require(auction_.start > 0, "Vault not under auction");

        // If offering too much fyToken, take only the necessary.
        artIn = maxArtIn > auction_.art ? auction_.art : maxArtIn;

        // Calculate the collateral to be sold
        (liquidatorCut, auctioneerCut) = _calcPayout(auction_, to, artIn);
        require(liquidatorCut >= minInkOut, "Not enough bought");

        // Update Cauldron and local auction data
        _updateAccounting(
            vaultId,
            auction_,
            liquidatorCut + auctioneerCut,
            artIn
        );

        // Move the assets
        _payInk(auction_, to, liquidatorCut, auctioneerCut);
        if (artIn != 0) {
            // Burn fyToken from liquidator
            cauldron.series(auction_.seriesId).fyToken.burn(msg.sender, artIn);
        }

        _collateralBought(vaultId, to, liquidatorCut + auctioneerCut, artIn);
    }

    /// @dev transfers funds from the ilkJoin to the liquidator (and potentially the auctioneer if they're differente people)
    function _payInk(
        DataTypes.Auction memory auction_,
        address to,
        uint256 liquidatorCut,
        uint256 auctioneerCut
    ) internal {
        // If liquidatorCut is 0, then auctioneerCut is 0 too, so no need to double check
        if (liquidatorCut > 0) {
            IJoin ilkJoin = ladle.joins(auction_.ilkId);
            require(ilkJoin != IJoin(address(0)), "Join not found");

            // Pay auctioneer's cut if necessary
            if (auctioneerCut > 0) {
                ilkJoin.exit(auction_.auctioneer, auctioneerCut.u128());
            }

            // Give collateral to the liquidator
            ilkJoin.exit(to, liquidatorCut.u128());
        }
    }

    /// @notice Update accounting on the Witch and on the Cauldron. Delete the auction and give back the vault if finished.
    /// This function doesn't verify the vaultId matches the vault and auction passed. Check before calling.
    function _updateAccounting(
        bytes12 vaultId,
        DataTypes.Auction memory auction_,
        uint256 inkOut,
        uint256 artIn
    ) internal {
        // Duplicate check, but guarantees data integrity
        require(auction_.start > 0, "Vault not under auction");

        // Update concurrent collateral under auction
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
                require(
                    auction_.art - artIn >= debt.min * (10**debt.dec),
                    "Leaves dust"
                );

                // Update the auction
                auction_.ink -= inkOut.u128();
                auction_.art -= artIn.u128();

                // Store auction changes
                auctions[vaultId] = auction_;

                // Update limits - reduce it by whatever was bought
                limits_.sum -= inkOut.u128();
            }
        }

        // Store limit changes
        limits[auction_.ilkId][auction_.baseId] = limits_;

        // Update accounting at Cauldron
        cauldron.slurp(vaultId, inkOut.u128(), artIn.u128());
    }

    /// @dev Logs that a certain amount of a vault was liquidated
    /// Useful as a method so it can be overriden by specialised witches that may need to do extra accounting or notify 3rd parties
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
    The Join  then dishes out the collateral   :.          \\,----,         ,;
    to you, dear user. And the debt is          `.`--.___   (    /  ___.--','
    settled with the base join or debt fyToken.   `.     ``-----'-''     ,'
                                                    -.               ,-
                                                       `-._______.-'gpyy


    */
    /// @dev quoutes hoy much ink a liquidator is expected to get if it repays an `artIn` amount
    /// Works for both Auctioned and ToBeAuctioned vaults
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
            auction_ = _calcAuction(vault, series, to, balances, debt);
        }

        // GT check is to cater for partial buys right before this method executes
        artIn = maxArtIn > auction_.art ? auction_.art : maxArtIn;

        (liquidatorCut, auctioneerCut) = _calcPayout(auction_, to, artIn);
    }

    /// @notice Return how much collateral should be given out.
    function _calcPayout(
        DataTypes.Auction memory auction_,
        address to,
        uint256 artIn
    ) internal view returns (uint256 liquidatorCut, uint256 auctioneerCut) {
        // Calculate how much collateral to give for paying a certain amount of debt, at a certain time, for a certain vault.
        // inkOut = (artIn / totalArt) * totalInk * (p + (1 - p) * t)
        DataTypes.Line memory line_ = lines[auction_.ilkId][
            auction_.baseId
        ];
        uint256 duration = line_.duration;
        uint256 initialProportion = line_.initialOffer;

        // If the world has not turned to ashes and darkness, auctions will malfunction on
        // the 7th of February 2106, at 06:28:16 GMT
        // TODO: Replace this contract before then 😰
        // UPDATE: Added reminder to Google calendar ✅
        uint256 elapsed;
        uint256 proportionNow;
        unchecked {
            elapsed = uint32(block.timestamp) - uint256(auction_.start); // Overflow on block.timestamp is fine
        }
        if (duration == type(uint32).max) {     // Interpreted as infinite duration
            proportionNow = initialProportion;
        } else if (elapsed > duration) {
            proportionNow = 1e18;
        } else {
            proportionNow =
                uint256(initialProportion) +
                uint256(1e18 - initialProportion).wmul(elapsed.wdiv(duration));
        }

        uint256 inkAtEnd = uint256(artIn).wdiv(auction_.art).wmul(auction_.ink);
        liquidatorCut = inkAtEnd.wmul(proportionNow);
        if (auction_.auctioneer != to) {
            auctioneerCut = liquidatorCut.wmul(auctioneerReward);
            liquidatorCut -= auctioneerCut;
        }
    }
}
