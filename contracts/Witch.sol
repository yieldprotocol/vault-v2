// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/vault-interfaces/ILadle.sol";
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

/// @title  The Witch is a Auction/Liquidation Engine for the Yield protocol
/// @notice The Witch grabs uncollateralized vaults, replacing the owner by itself. Then it sells
/// part or all of the vault collateral in exchange for underlying or fyTokens to pay its debt.
/// The amount of collateral given increases over time, until it offers to sell all the collateral
/// under auction if repaying all the debt under auction. The auction is held open at the final price
/// indefinitely. After the debt is settled, the Witch returns the vault to its original owner.
contract Witch is AccessControl {
    using WMul for uint256;
    using WDiv for uint256;
    using CastU256U128 for uint256;

    event Auctioned(bytes12 indexed vaultId, uint256 indexed start);
    event Bought(bytes12 indexed vaultId, address indexed buyer, uint256 ink, uint256 art);
    event LineSet(bytes6 indexed ilkId, bytes6 baseId, uint32 duration, uint64 proportion, uint64 initialOffer);
    event LimitSet(bytes6 indexed ilkId, bytes6 baseId, uint96 max, uint24 dust, uint8 dec);
    event Point(bytes32 indexed param, address indexed value);

    struct Auction {
        address owner;
        uint32 start;
        bytes6 baseId; // We cache the baseId here
        uint128 art;
        uint128 ink;
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
        lines[ilkId][baseId] = Line({
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
    function auction(bytes12 vaultId) external {
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
        limits_.sum += balances.ink;
        limits[vault.ilkId][series.baseId] = limits_;

        // We store the proportion of the vault to auction, which is the whole vault if the debt would be below dust.
        Line storage line = lines[vault.ilkId][series.baseId];
        uint128 art = uint256(balances.art).wmul(line.proportion).u128();
        if (art < limits_.dust) art = balances.art;
        uint128 ink = (art == balances.art) ? balances.ink : uint256(balances.ink).wmul(line.proportion).u128();

        auctions[vaultId] = Auction({
            owner: vault.owner,
            start: uint32(block.timestamp), // Overflow is desired
            baseId: series.baseId,
            art: art,
            ink: ink
        });

        // The Witch is now in control of the vault under auction
        // TODO: Consider using `stir` to take only the part of the vault being auctioned.
        cauldron.give(vaultId, address(this));
        emit Auctioned(vaultId, uint32(block.timestamp));
    }

    /// @dev Pay all debt from a vault in liquidation, getting at least `minInkOut` collateral.
    /// @param vaultId Id of vault to buy
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @return inkOut Amount of vault collateral sold
    function payBase(bytes12 vaultId, uint128 minInkOut) external returns (uint256 inkOut) {
        Auction storage auction_ = auctions[vaultId];
        require(
            auction_.start > 0,
            "Vault not under auction"
        );

        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        DataTypes.Series memory series = cauldron.series(vault.seriesId);

        // Find out how much the debt is worth
        uint128 baseIn = cauldron.debtToBase(vault.seriesId, auction_.art);

        require(
            (inkOut = _liquidate(vaultId, vault, auction_)) >= minInkOut,
            "Not enough bought"
        );

        // Give collateral to the user
        IJoin ilkJoin = ladle.joins(vault.ilkId);
        require(ilkJoin != IJoin(address(0)), "Join not found");
        ilkJoin.exit(msg.sender, inkOut.u128());

        // Take underlying from user
        IJoin baseJoin = ladle.joins(series.baseId);
        require(baseJoin != IJoin(address(0)), "Join not found");
        baseJoin.join(msg.sender, baseIn);
    }

    /// @dev Pay all debt from a vault in liquidation, getting at least `minInkOut` collateral.
    /// @param vaultId Id of vault to buy
    /// @param minInkOut Minimum amount of collateral that must be received
    /// @return inkOut Amount of vault collateral sold
    function payFYToken(bytes12 vaultId, uint128 minInkOut) external returns (uint256 inkOut) {
        Auction storage auction_ = auctions[vaultId];
        require(
            auction_.start > 0,
            "Vault not under auction"
        );

        DataTypes.Vault memory vault = cauldron.vaults(vaultId);

        require(
            (inkOut = _liquidate(vaultId, vault, auction_)) >= minInkOut,
            "Not enough bought"
        );

        // Give collateral to the user
        IJoin ilkJoin = ladle.joins(vault.ilkId);
        require(ilkJoin != IJoin(address(0)), "Join not found");
        ilkJoin.exit(msg.sender, inkOut.u128());

        // Burn fyToken from user
        DataTypes.Series memory series = cauldron.series(vault.seriesId);
        series.fyToken.burn(msg.sender, auction_.art);
    }

/*

     x x x
   x      x    Hi Fren!
  x  .  .  x   I want to buy this vault under auction!  I'll pay
  x        x   you in the same `base` currency of the debt, but
  x        x   I want no less than `uint min` of the collateral, ok?
  x   ===  x
   x       x
    xxxxxxx
       x                            __  Ok Fren!
       x     ┌───────────┐  _(\    |@@|
       xxxxxx│BASE BUCKS │ (__/\__ \--/ __
       x     │   $$$     │    \___|----|  |   __
       x     └───────────┘        \ }{ /\ )_ / _\
      x x                         /\__/\ \__O (__
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
 The Ladle then dishes out the collateral   :.          \\,----,         ,;
 to you, dear user.  And the base you        `.`--.___   (    /  ___.--','
 paid is settled up with the join.             `.     ``-----'-''     ,'
                                                  -.               ,-
                                                     `-._______.-'gpyy


*/

    /// @notice Remove debt from a vault, and return how much collateral should be given out.
    /// Auction limits apply.
    /// @dev If the debt is returned to zero, the vault is returned to its original owner.
    /// This function doesn't verify the vaultId matches the vault and balances passed. Check before calling.
    function _liquidate(
        bytes12 vaultId,
        DataTypes.Vault memory vault,
        Auction storage auction
    ) private returns (uint256 inkOut) {
        Auction memory auction_ = auctions[vaultId];
        // Duplicate check, but guarantees data integrity
        require(
            auction_.start > 0,
            "Vault not under auction"
        );

        {
            // Calculate how much collateral to give for liquidating at a certain time, for a certain vault.
            // inkOut = totalInk * (p + (1 - p) * t)
            uint256 proportionNow = _calcProportion(vault.ilkId, auction_.baseId, auction_.start);
            inkOut = uint256(auction.ink).wmul(proportionNow);
        }

        {
            // Update concurrent collateral under auction
            Limits memory limits_ = limits[vault.ilkId][auction_.baseId];
            limits_.sum -= inkOut.u128();
            limits[vault.ilkId][auction_.baseId] = limits_;
        }

        // Remove debt and collateral from vault
        cauldron.slurp(vaultId, inkOut.u128(), auction_.art);

        // If there is no debt left, return the vault with the collateral to the owner
        delete auctions[vaultId];
        cauldron.give(vaultId, auction_.owner);

        emit Bought(vaultId, msg.sender, inkOut, auction_.art);
    }

    /// @notice Calculate the proportion of collateral to give out, based on the max chosen by governance and time passed, with 18 decimals.
    function _calcProportion(bytes6 ilkId, bytes6 baseId, uint32 auctionStart) private view returns (uint256 proportion) {
        Line memory line_ = lines[ilkId][baseId];
        uint256 duration = line_.duration;
        uint256 initialProportion = line_.initialOffer;

        // If the world has not turned to ashes and darkness, auctions will malfunction on
        // the 7th of February 2106, at 06:28:16 GMT
        // TODO: Replace this contract before then 😰
        // UPDATE: Added reminder to Google calendar ✅
        uint256 elapsed;
        unchecked {
            elapsed = uint32(block.timestamp) - auctionStart;
        }
        uint256 timeProportion = elapsed > duration ? 1e18 : elapsed.wdiv(duration);
        proportion = uint256(initialProportion) + uint256(1e18 - initialProportion).wmul(timeProportion);
    }
}
