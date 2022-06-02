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

/// @title  The Witch is a Auction/Liquidation Engine for the Yield protocol
/// @notice The Witch grabs uncollateralized vaults, replacing the owner by itself. Then it sells
/// the vault collateral in exchange for underlying to pay its debt. The amount of collateral
/// given increases over time, until it offers to sell all the collateral for underlying to pay
/// all the debt. The auction is held open at the final price indefinitely.
/// @dev After the debt is settled, the Witch returns the vault to its original owner.
contract WitchV2 is AccessControl {
    using WMul for uint256;
    using WDiv for uint256;
    using CastU256U128 for uint256;

    event Auctioned(bytes12 indexed vaultId, uint256 indexed start);
    event Cancelled(bytes12 indexed vaultId);
    event Bought(bytes12 indexed vaultId, address indexed buyer, uint256 ink, uint256 art);
    event LineSet(bytes6 indexed ilkId, bytes6 indexed baseId, uint32 duration, uint64 proportion, uint64 initialOffer);
    event LimitSet(bytes6 indexed ilkId, bytes6 indexed baseId, uint96 max, uint24 dust, uint8 dec);
    event Point(bytes32 indexed param, address indexed value);

    struct Auction {
        address owner;
        uint32 start;
        bytes6 baseId; // We cache the baseId here
        uint128 ink;
        uint128 art;
    }

    struct Line {
        uint32 duration; // Time that auctions take to go to minimal price and stay there
        uint64 proportion; // Proportion of the vault that is available each auction (1e18 = 100%)
        uint64 initialOffer; // Proportion of collateral that is sold at auction start (1e18 = 100%)
    }

    struct Limits {
        uint96 max; // Maximum concurrent auctioned collateral
        uint24 dust; // Minimum collateral that must be left when buying, unless buying all
        uint8 dec; // Multiplying factor (10**dec) for max and dust
        uint128 sum; // Current concurrent auctioned collateral
    }

    ICauldron public immutable cauldron;
    ILadle public ladle;
    mapping(bytes12 => Auction) public auctions;
    mapping(bytes6 => mapping(bytes6 => Line)) public lines;
    mapping(bytes6 => mapping(bytes6 => Limits)) public limits;

    constructor(ICauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

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
        require(initialOffer == 0 || initialOffer >= 0.01e18, "InitialOffer below 1%");
        require(proportion >= 0.01e18, "Proportion below 1%");
        lines[ilkId][baseId] = Line({duration: duration, proportion: proportion, initialOffer: initialOffer});
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
    /// @param dust Minimum collateral that must be left when buying, unless buying all
    /// @param dec Multiplying factor (10**dec) for max and dust
    function setLimit(
        bytes6 ilkId,
        bytes6 baseId,
        uint96 max,
        uint24 dust,
        uint8 dec
    ) external auth {
        limits[ilkId][baseId] = Limits({
            max: max,
            dust: dust,
            dec: dec,
            sum: limits[ilkId][baseId].sum // sum is initialized at zero, and doesn't change when changing any ilk parameters
        });
        emit LimitSet(ilkId, baseId, max, dust, dec);
    }

    /// @dev Put an undercollateralized vault up for liquidation
    /// @param vaultId Id of vault to liquidate
    function auction(bytes12 vaultId) external returns (Auction memory auction_) {
        require(auctions[vaultId].start == 0, "Vault already under auction");
        require(cauldron.level(vaultId) < 0, "Not undercollateralized");

        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        DataTypes.Series memory series = cauldron.series(vault.seriesId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        // There is a limit on how much collateral can be concurrently put at auction, but it is a soft limit.
        // If the limit has been surpassed, no more vaults of that collateral can be put for auction.
        // This avoids the scenario where some vaults might be too large to be auctioned.
        Limits memory limits_ = limits[vault.ilkId][series.baseId];
        require(limits_.sum <= limits_.max * (10**limits_.dec), "Collateral limit reached");

        auction_ = _auction(vault, series, balances, limits_);

        limits_.sum += auction_.ink;
        limits[vault.ilkId][series.baseId] = limits_;

        auctions[vaultId] = auction_;

        // The Witch is now in control of the vault under auction
        // TODO: Consider using `stir` to take only the part of the vault being auctioned.
        cauldron.give(vaultId, address(this));
        emit Auctioned(vaultId, uint32(block.timestamp));
    }

    function _auction(
        DataTypes.Vault memory vault,
        DataTypes.Series memory series,
        DataTypes.Balances memory balances,
        Limits memory limits_
    ) internal view returns (Auction memory) {
        // We store the proportion of the vault to auction, which is the whole vault if the debt would be below dust.
        Line storage line = lines[vault.ilkId][series.baseId];
        uint128 art = uint256(balances.art).wmul(line.proportion).u128();
        if (art < limits_.dust * (10**limits_.dec)) art = balances.art;
        uint128 ink = (art == balances.art) ? balances.ink : uint256(balances.ink).wmul(line.proportion).u128();

        return
            Auction({
                owner: vault.owner,
                start: uint32(block.timestamp), // Overflow is fine
                baseId: series.baseId,
                art: art,
                ink: ink
            });
    }

    /// @dev Cancel an auction for a vault that isn't undercollateralized anymore
    /// @param vaultId Id of vault to return
    function cancel(bytes12 vaultId) external {
        Auction storage auction_ = auctions[vaultId];
        require(auction_.start != 0, "Vault not under auction");
        require(cauldron.level(vaultId) >= 0, "Undercollateralized");

        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        DataTypes.Series memory series = cauldron.series(vault.seriesId);

        // Update concurrent collateral under auction
        limits[vault.ilkId][series.baseId].sum -= auction_.ink;

        cauldron.give(vaultId, auction_.owner);
        delete auctions[vaultId];

        emit Cancelled(vaultId);
    }

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
    ) external returns (uint256 inkOut, uint256 baseIn) {
        Auction memory auction_ = auctions[vaultId];
        require(auction_.start > 0, "Vault not under auction");

        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        DataTypes.Series memory series = cauldron.series(vault.seriesId);

        // Find out how much debt is being repaid
        uint128 artIn = uint128(cauldron.debtFromBase(vault.seriesId, maxBaseIn));

        // If offering too much base, take only the necessary.
        artIn = artIn > auction_.art ? auction_.art : artIn;
        baseIn = cauldron.debtToBase(vault.seriesId, artIn);

        // Calculate the collateral to be sold
        require(
            (inkOut = _calcPayout(vault.ilkId, auction_.baseId, auction_, artIn)) >= minInkOut,
            "Not enough bought"
        );

        // Update Cauldron and local auction data
        _updateAccounting(vaultId, vault.ilkId, auction_.baseId, auction_, inkOut, artIn);

        // Move the assets
        if (inkOut != 0) {
            // Give collateral to the user
            IJoin ilkJoin = ladle.joins(vault.ilkId);
            require(ilkJoin != IJoin(address(0)), "Join not found");
            ilkJoin.exit(to, inkOut.u128());
        }
        if (baseIn != 0) {
            // Take underlying from user
            IJoin baseJoin = ladle.joins(series.baseId);
            require(baseJoin != IJoin(address(0)), "Join not found");
            baseJoin.join(msg.sender, baseIn.u128());
        }
    }

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
    ) external returns (uint256 inkOut, uint256 artIn) {
        Auction memory auction_ = auctions[vaultId];
        require(auction_.start > 0, "Vault not under auction");

        DataTypes.Vault memory vault = cauldron.vaults(vaultId);

        // If offering too much fyToken, take only the necessary.
        artIn = maxArtIn > auction_.art ? auction_.art : maxArtIn;

        // Calculate the collateral to be sold
        require(
            (inkOut = _calcPayout(vault.ilkId, auction_.baseId, auction_, artIn)) >= minInkOut,
            "Not enough bought"
        );

        // Update Cauldron and local auction data
        _updateAccounting(vaultId, vault.ilkId, auction_.baseId, auction_, inkOut, artIn);

        // Move the assets
        if (inkOut != 0) {
            // Give collateral to the user
            IJoin ilkJoin = ladle.joins(vault.ilkId);
            require(ilkJoin != IJoin(address(0)), "Join not found");
            ilkJoin.exit(to, inkOut.u128());
        }
        if (artIn != 0) {
            // Burn fyToken from user
            DataTypes.Series memory series = cauldron.series(vault.seriesId);
            series.fyToken.burn(msg.sender, artIn);
        }

        emit Bought(vaultId, to, inkOut, artIn);
    }

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
    function calcPayout(bytes12 vaultId, uint256 artIn) external view returns (uint256 inkOut) {
        Auction memory auction_ = auctions[vaultId];
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);

        if (auction_.ink == 0) {
            DataTypes.Series memory series = cauldron.series(vault.seriesId);
            DataTypes.Balances memory balances = cauldron.balances(vaultId);
            Limits memory limits_ = limits[vault.ilkId][series.baseId];
            auction_ = _auction(vault, series, balances, limits_);
        }

        inkOut = _calcPayout(vault.ilkId, auction_.baseId, auction_, artIn);
    }

    /// @notice Return how much collateral should be given out.
    function _calcPayout(
        bytes6 ilkId,
        bytes6 baseId,
        Auction memory auction_,
        uint256 artIn
    ) internal view returns (uint256 inkOut) {
        // Calculate how much collateral to give for paying a certain amount of debt, at a certain time, for a certain vault.
        // inkOut = (artIn / totalArt) * totalInk * (p + (1 - p) * t)
        Line memory line_ = lines[ilkId][baseId];
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
        if (elapsed > duration || initialProportion == 1e18) {
            proportionNow = 1e18;
        } else {
            proportionNow = uint256(initialProportion) + uint256(1e18 - initialProportion).wmul(elapsed.wdiv(duration));
        }

        uint256 inkAtEnd = uint256(artIn).wdiv(auction_.art).wmul(auction_.ink);
        inkOut = inkAtEnd.wmul(proportionNow);
    }

    /// @notice Update accounting on the Witch and on the Cauldron. Delete the auction and give back the vault if finished.
    /// This function doesn't verify the vaultId matches the vault and auction passed. Check before calling.
    function _updateAccounting(
        bytes12 vaultId,
        bytes6 ilkId,
        bytes6 baseId,
        Auction memory auction_,
        uint256 inkOut,
        uint256 artIn
    ) internal {
        // Duplicate check, but guarantees data integrity
        require(auction_.start > 0, "Vault not under auction");

        // Update concurrent collateral under auction
        Limits memory limits_ = limits[ilkId][baseId];
        limits_.sum -= inkOut.u128();
        limits[ilkId][baseId] = limits_;

        // Update local auction
        {
            if (auction_.art == artIn) {
                // If there is no debt left, return the vault with the collateral to the owner
                cauldron.give(vaultId, auction_.owner);
                delete auctions[vaultId];
            } else {
                // Ensure enough dust is left
                require(auction_.art - artIn >= limits_.dust * (10**limits_.dec), "Leaves dust");

                // Update the auction
                auction_.ink -= inkOut.u128();
                auction_.art -= artIn.u128();
            }
        }

        // Update accounting at Cauldron
        cauldron.slurp(vaultId, inkOut.u128(), artIn.u128());
    }
}