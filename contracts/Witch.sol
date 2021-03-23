// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/ILadle.sol";
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";


library Math {
    /// @dev Minimum of two unsigned integers
    function min(uint128 x, uint128 y) internal pure returns (uint128) {
        return x < y ? x : y;
    }
}

library RMath {
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            uint256 _z = uint256(x) * uint256(y) / 1e27;
            require (_z <= type(uint128).max, "RMUL Overflow");
            z = uint128(_z);
        }
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds down.
    function rdiv(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            require (y > 0, "RDIV by zero");
            uint256 _z = uint256(x) * 1e27 / y;
            require (_z <= type(uint128).max, "RDIV Overflow");
            z = uint128(_z);
        }
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds up.
    function rdivup(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            require (y > 0, "RDIVUP by zero");
            uint256 _z = uint256(x) * 1e27 % y == 0 ? uint256(x) * 1e27 / y : uint256(x) * 1e27 / y + 1;
            require (_z <= type(uint128).max, "RDIV Overflow");
            z = uint128(_z);
        }
    }
}

// TODO: Add a setter for AUCTION_TIME
contract Witch {
    using RMath for uint128;

    event Bought(address indexed buyer, bytes12 indexed vaultId, uint128 ink, uint128 art);
  
    uint128 constant public AUCTION_TIME = 4 * 60 * 60; // Time that auctions take to go to minimal price and stay there.
    ICauldron immutable public cauldron;
    ILadle immutable public ladle;

    constructor (ICauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

    /// @dev Put an undercollateralized vault up for liquidation.
    function grab(bytes12 vaultId) public {
        cauldron.grab(vaultId);
    }

    /// @dev Buy an amount of collateral off a vault in liquidation, paying at most `max` underlying.
    function buy(bytes12 vaultId, uint128 art, uint128 min) public {
        DataTypes.Balances memory balances_ = cauldron.balances(vaultId);

        require (balances_.art > 0, "Nothing to buy");                                      // Cheapest way of failing gracefully if given a non existing vault
        uint128 elapsed = uint32(block.timestamp) - cauldron.timestamps(vaultId);           // Auctions will malfunction on the 7th of February 2106, at 06:28:16 GMT, we should replace this contract before then.
        uint128 price;
        {
            // Price of a collateral unit, in underlying, at the present moment, for a given vault
            //
            //                ink       1      min(auction, elapsed)
            // price = 1 / (------- * (--- + -----------------------))
            //                art       2       2 * auction
            // solhint-disable-next-line var-name-mixedcase
            uint128 RAY = 1e27;
            uint128 term1 = balances_.ink.rdiv(balances_.art);
            uint128 term2 = RAY / 2;
            uint128 dividend3 = Math.min(AUCTION_TIME, elapsed);
            uint128 divisor3 = AUCTION_TIME * 2;
            uint128 term3 = dividend3.rdiv(divisor3);
            price = RAY.rdiv(term1.rmul(term2 + term3));
        }
        uint128 ink = art.rdivup(price);                                                    // Calculate collateral to sell. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        require (ink >= min, "Not enough bought");                                          // TODO: We could also check that min <= balances_.ink

        ladle.settle(vaultId, msg.sender, ink, art);                                        // Move the assets
        if (balances_.art - art == 0 && balances_.ink - ink == 0) cauldron.destroy(vaultId);

        emit Bought(msg.sender, vaultId, ink, art);
    }
}