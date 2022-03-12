// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/vault-interfaces/ILadle.sol";
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WMulUp.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";
import "@yield-protocol/utils-v2/contracts/math/WDivUp.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U32.sol";

/// @title  The Witch is a Auction/Liquidation Engine for the Yield protocol
/// @notice The Witch grabs uncollateralized vaults, replacing the owner by itself. Then it sells
/// the vault collateral in exchange for underlying to pay its debt. The amount of collateral
/// given increases over time, until it offers to sell all the collateral for underlying to pay
/// all the debt. The auction is held open at the final price indefinitely.
/// @dev After the debt is settled, the Witch returns the vault to its original owner.
contract Witch is AccessControl {
    using WMul for uint256;
    using WMulUp for uint256;
    using WDiv for uint256;
    using WDivUp for uint256;
    using CastU256U128 for uint256;
    using CastU256U32 for uint256;

    event Auctioned(bytes12 indexed vaultId, uint256 indexed start);
    event Bought(bytes12 indexed vaultId, address indexed buyer, uint256 ink, uint256 art);
    event IlkSet(bytes6 indexed ilkId, uint32 duration, uint64 initialOffer, uint96 line, uint24 dust, uint8 dec);
    event Point(bytes32 indexed param, address indexed value);

    struct Auction {
        address owner;
        uint32 start;
    }

    struct Ilk {
        uint32 duration; // Time that auctions take to go to minimal price and stay there
        uint64 initialOffer; // Proportion of collateral that is sold at auction start (1e18 = 100%)
    }

    struct Limits {
        uint96 line; // Maximum concurrent auctioned collateral
        uint24 dust; // Minimum collateral that must be left when buying, unless buying all
        uint8 dec; // Multiplying factor (10**dec) for line and dust
        uint128 sum; // Current concurrent auctioned collateral
    }

    struct BuyParamas {
        bytes6 ilkId;
        bytes6 baseId;
        bytes12 vaultId;
        uint128 totalInk;
        uint128 artIn;
        uint128 totalArt;
        uint128 base;
        uint128 min;
    }

    ICauldron public immutable cauldron;
    ILadle public ladle;
    mapping(bytes12 => Auction) public auctions;
    mapping(bytes6 => Ilk) public ilks;
    mapping(bytes6 => Limits) public limits;

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

    /// @dev Governance function to set:
    ///  - the auction duration to calculate liquidation prices
    ///  - the proportion of the collateral that will be sold at auction start
    ///  - the maximum collateral that can be auctioned at the same time
    ///  - the minimum collateral that must be left when buying, unless buying all
    ///  - The decimals for maximum and minimum
    /// @param ilkId Id of asset used for collateral
    /// @param duration Time that auctions take to go to minimal price
    /// @param initialOffer Proportion of collateral that is sold at auction start (1e18 = 100%)
    /// @param line Maximum concurrent auctioned collateral
    /// @param dust Minimum collateral that must be left when buying, unless buying all
    /// @param dec Multiplying factor (10**dec) for line and dust
    function setIlk(
        bytes6 ilkId,
        uint32 duration,
        uint64 initialOffer,
        uint96 line,
        uint24 dust,
        uint8 dec
    ) external auth {
        require(initialOffer <= 1e18, "Only at or under 100%");
        ilks[ilkId] = Ilk({duration: duration, initialOffer: initialOffer});
        limits[ilkId] = Limits({
            line: line,
            dust: dust,
            dec: dec,
            sum: limits[ilkId].sum // sum is initialized at zero, and doesn't change when changing any ilk parameters
        });
        emit IlkSet(ilkId, duration, initialOffer, line, dust, dec);
    }

    /// @dev Put an undercollateralized vault up for liquidation
    /// @param vaultId Id of vault to liquidate
    function auction(bytes12 vaultId) external {
        require(auctions[vaultId].start == 0, "Vault already under auction");
        require(cauldron.level(vaultId) < 0, "Not undercollateralized");

        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);
        DataTypes.Balances memory balances_ = cauldron.balances(vaultId);
        Limits memory limits_ = limits[vault_.ilkId];
        limits_.sum += balances_.ink;
        require(limits_.sum <= limits_.line * (10**limits_.dec), "Collateral limit reached");

        limits[vault_.ilkId] = limits_;
        auctions[vaultId] = Auction({owner: vault_.owner, start: block.timestamp.u32()});
        cauldron.give(vaultId, address(this));
        emit Auctioned(vaultId, block.timestamp.u32());
    }

    /// @dev Pay `base` of the debt in a vault in liquidation, getting at least `min` collateral.
    /// Use `payAll` to pay all the debt, using `buy` for amounts close to the whole vault might revert.
    /// @param vaultId Id of vault to buy
    /// @param base Amount of base to pay
    /// @param min Minimum amount of collateral that must be received
    /// @return ink Amount of vault collateral sold
    function buy(
        bytes12 vaultId,
        uint128 base,
        uint128 min
    ) external returns (uint256 ink) {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);
        DataTypes.Balances memory balances_ = cauldron.balances(vaultId);
        require(balances_.art > 0, "Nothing to buy"); // Cheapest way of failing gracefully if given a non existing vault

        uint128 artIn = uint128(cauldron.debtFromBase(vault_.seriesId, base));

        BuyParamas memory buyParamas = BuyParamas(
            vault_.ilkId,
            cauldron.series(vault_.seriesId).baseId,
            vaultId,
            balances_.ink,
            artIn,
            balances_.art,
            base,
            min
        );

        ink = _buy(buyParamas);
    }

    /// @dev Pay all debt from a vault in liquidation, getting at least `min` collateral.
    /// @param vaultId Id of vault to buy
    /// @param min Minimum amount of collateral that must be received
    /// @return ink Amount of vault collateral sold
    function payAll(bytes12 vaultId, uint128 min) external returns (uint256 ink) {
        Auction memory auction_ = auctions[vaultId];
        require(auction_.start > 0, "Vault not under auction");
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);
        DataTypes.Balances memory balances_ = cauldron.balances(vaultId);
        require(balances_.art > 0, "Nothing to buy"); // Cheapest way of failing gracefully if given a non existing vault


        BuyParamas memory buyParamas = BuyParamas(
            vault_.ilkId,
            cauldron.series(vault_.seriesId).baseId,
            vaultId,
            balances_.ink,
            balances_.art,
            balances_.art,
            cauldron.debtToBase(vault_.seriesId, balances_.art),
            min
        );

        ink = _buy(buyParamas);

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

    function _buy(BuyParamas memory buyParamas) private returns (uint256 inkOut) {
        Auction memory auction_ = auctions[buyParamas.vaultId];
        require(auction_.start != 0, "Vault not under auction");

        //          (      a         )
        // inkOut = (artIn / totalArt) * totalInk * (p + (1 - p) * t)
        uint256 a = uint256(buyParamas.artIn).wdivup(buyParamas.totalArt);
        (uint256 t, uint64 p) = _calculateT(buyParamas.ilkId, auction_.start);
        inkOut = a.wmul(buyParamas.totalInk).wmulup(uint256(p) + uint256(1e18 - p).wmulup(t));
        require(inkOut >= buyParamas.min, "Not enough bought");

        Limits memory limits_ = limits[buyParamas.ilkId];

        // Ensure enough dust is left
        require(buyParamas.totalArt == buyParamas.artIn || buyParamas.totalInk - inkOut >= limits_.dust * (10**limits_.dec), "Leaves dust");

        // Update sum
        limits[buyParamas.ilkId].sum = limits_.sum - inkOut.u128();

        cauldron.slurp(buyParamas.vaultId, inkOut.u128(), buyParamas.artIn); // Remove debt and collateral from vault

        _settle(msg.sender, buyParamas.ilkId, buyParamas.baseId, inkOut.u128(), buyParamas.base); // Move the assets

        if (buyParamas.totalArt - buyParamas.artIn == 0) {
            // If there is no debt left, return the vault with the collateral to the owner
            cauldron.give(buyParamas.vaultId, auction_.owner);
            delete auctions[buyParamas.vaultId];
        }

        if (inkOut > buyParamas.totalInk) {
            inkOut = buyParamas.totalInk;
        }

        // Still using the initially read `art` value, not the updated one
        emit Bought(buyParamas.vaultId, msg.sender, inkOut, buyParamas.artIn);
    }

    function _calculateT(bytes6 ilkId, uint32 auctionStart) private view returns (uint256 t, uint64 p) {
        Ilk memory ilk_ = ilks[ilkId];
        uint32 duration = ilk_.duration;
        p = ilk_.initialOffer;

        // If the world has not turned to ashes and darkness, auctions will malfunction on
        // the 7th of February 2106, at 06:28:16 GMT
        // TODO: Replace this contract before then 😰
        // UPDATE: Added reminder to Google calendar ✅
        uint256 elapsed;
        unchecked {
            elapsed = uint32(block.timestamp) - auctionStart;
        }
        t = elapsed > duration ? 1e18 : elapsed.wdivup(duration);
    }

    /// @dev Move base from the buyer to the protocol, and collateral from the protocol to the buyer
    /// @param user  Address of buyer
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of borrowed token
    /// @param ink Amount of collateral
    /// @param art Amount of debt
    function _settle(
        address user,
        bytes6 ilkId,
        bytes6 baseId,
        uint128 ink,
        uint128 art
    ) private {
        if (ink != 0) {
            // Give collateral to the user
            IJoin ilkJoin = ladle.joins(ilkId);
            require(ilkJoin != IJoin(address(0)), "Join not found");
            ilkJoin.exit(user, ink);
        }
        if (art != 0) {
            // Take underlying from user
            IJoin baseJoin = ladle.joins(baseId);
            require(baseJoin != IJoin(address(0)), "Join not found");
            baseJoin.join(user, art);
        }
    }
}
