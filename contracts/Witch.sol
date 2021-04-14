// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/ILadle.sol";
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";


library WitchMath {
    /// @dev Minimum of two unsigned integers
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
}

library WitchRMath {
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / 1e27;
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds down.
    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * 1e27 / y;
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds up.
    function rdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * 1e27 % y == 0 ? x * 1e27 / y : x * 1e27 / y + 1;
    }
}

library WitchSafe256 {
    /// @dev Safely cast an uint256 to an uint128
    function u128(uint256 x) internal pure returns (uint128 y) {
        require (x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }
}

// TODO: Add a setter for AUCTION_TIME
contract Witch {
    using WitchRMath for uint256;
    using WitchSafe256 for uint256;

    event Bought(address indexed buyer, bytes12 indexed vaultId, uint256 ink, uint256 art);
  
    uint256 constant public AUCTION_TIME = 4 * 60 * 60; // Time that auctions take to go to minimal price and stay there.
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
        uint256 elapsed = uint32(block.timestamp) - cauldron.timestamps(vaultId);           // Auctions will malfunction on the 7th of February 2106, at 06:28:16 GMT, we should replace this contract before then.
        uint256 price;
        {
            // Price of a collateral unit, in underlying, at the present moment, for a given vault
            //
            //                ink       1      min(auction, elapsed)
            // price = 1 / (------- * (--- + -----------------------))
            //                art       2       2 * auction
            // solhint-disable-next-line var-name-mixedcase
            uint256 RAY = 1e27;
            uint256 term1 = uint256(balances_.ink).rdiv(balances_.art);
            uint256 term2 = RAY / 2;
            uint256 dividend3 = WitchMath.min(AUCTION_TIME, elapsed);
            uint256 divisor3 = AUCTION_TIME * 2;
            uint256 term3 = dividend3.rdiv(divisor3);
            price = RAY.rdiv(term1.rmul(term2 + term3));
        }
        uint256 ink = uint256(art).rdivup(price);                                                    // Calculate collateral to sell. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        require (ink >= min, "Not enough bought");

        ladle.settle(vaultId, msg.sender, ink.u128(), art);                                        // Move the assets
        if (balances_.art - art == 0 && balances_.ink - ink == 0) cauldron.destroy(vaultId);

        emit Bought(msg.sender, vaultId, ink, art);
    }
}