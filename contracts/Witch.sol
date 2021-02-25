// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/ICauldron.sol";
import "./interfaces/ILadle.sol";
import "./libraries/DataTypes.sol";


library Math {
    /// @dev Minimum of two unsigned integers
    function min(uint128 x, uint128 y) internal pure returns (uint128) {
        return x < y ? x : y;
    }
}

library RMath {
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        uint256 _z = uint256(x) * uint256(y) / 1e27;
        require (_z <= type(uint128).max, "RMUL Overflow");
        z = uint128(_z);
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds down.
    function rdiv(uint128 x, uint128 y) internal pure returns (uint128 z) {
        uint256 _z = uint256(x) * 1e27 / y;
        require (_z <= type(uint128).max, "RDIV Overflow");
        z = uint128(_z);
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds up.
    function rdivup(uint128 x, uint128 y) internal pure returns (uint128 z) {
        uint256 _z = uint256(x) * 1e27 % y == 0 ? uint256(x) * 1e27 / y : uint256(x) * 1e27 / y + 1;
        require (_z <= type(uint128).max, "RDIV Overflow");
        z = uint128(_z);
    }
}

contract Witch {
    using RMath for uint128;
  
    uint128 constant public AUCTION_TIME = 4 * 60 * 60; // Time that auctions take to go to minimal price and stay there.
    ICauldron immutable public cauldron;
    ILadle immutable public ladle;

    constructor (ICauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

    /// @dev Put an undercollateralized vault up for liquidation.
    function grab(bytes12 vaultId) public {
        cauldron._grab(vaultId);
    }

    /// @dev Buy an amount of collateral off a vault in liquidation, paying at most `max` underlying.
    function buy(bytes12 vaultId, uint128 dart, uint128 min) public {
        DataTypes.Balances memory balances = cauldron.vaultBalances(vaultId);                   // Cost of `cauldron.vaultBalances`
        require (balances.art >= 0, "Nothing to buy");                                          // Cheapest way of failing gracefully if given a non existing vault

        uint128 elapsed = uint128(block.timestamp) - cauldron.timestamps(vaultId);              // Cost of `cauldron.timestamps`
        uint128 price;
        {
            // Price of a collateral unit, in underlying, at the present moment, for a given vault
            //
            //                ink       1      min(auction, elapsed)
            // price = 1 / (------- * (--- + -----------------------))
            //                art       2       2 * auction
            uint128 RAY = 1e27;
            uint128 term1 = balances.ink.rdiv(balances.art);
            uint128 term2 = RAY / 2;
            uint128 dividend3 = Math.min(AUCTION_TIME, elapsed);
            uint128 divisor3 = AUCTION_TIME * 2;
            uint128 term3 = dividend3.rdiv(divisor3);
            price = uint128(RAY).rdiv(term1.rmul(term2 + term3));
        }
        uint128 dink = dart.rdivup(price);                                                      // Calculate collateral to sell. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        require (dink >= min, "Too expensive");

        balances = cauldron._slurp(vaultId, int128(dink), int128(dart));                        // Cost of `cauldron._slurp`  | Manipulate the vault | TODO: SafeCast
        ladle._join(vaultId, msg.sender, int128(dink), int128(dart));                           // Cost of `ladle._join`      | Move the assets | TODO: SafeCast
        if (balances.art == 0 && balances.ink == 0) cauldron.destroy(vaultId);                  // Cost of `cauldron.destroy`
    }

    /// @dev Return price of a collateral unit, in underlying, at the present moment, for a given vault
    //
    //                ink       1      min(auction, elapsed)
    // price = 1 / (------- * (--- + -----------------------))
    //                art       2       2 * auction
    /* function price(uint128 ink, uint128 art, uint128 elapsed) public pure returns (uint128) {
        uint128 RAY = 1e27;
        uint128 term1 = ink.rdiv(art);
        uint128 term2 = RAY / 2;
        uint128 dividend3 = Math.min(AUCTION_TIME, elapsed);
        uint128 divisor3 = AUCTION_TIME * 2;
        uint128 term3 = dividend3.rdiv(divisor3);
        price = RAY.rdiv(term1.rmul(term2 + term3));
    } */
}