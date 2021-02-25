// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/ICauldron.sol";
import "./interfaces/ILadle.sol";
import "./libraries/DataTypes.sol";


library Math {
    /// @dev Minimum of two unsigned integers
    function min(uint256 x, uint256 y) external pure returns (uint256) {
        return x < y ? x : y;
    }
}

library RMath {
    /// @dev Multiply x and y, with y being fixed point. Rounds down.
    function rmul(uint256 x, uint256 y) external pure returns (uint256) {
        return x * y / 1e27;
    }

    /// @dev Divide x and y, with y being fixed point. Rounds down.
    function rdiv(uint256 x, uint256 y) external pure returns (uint256) {
        return x * 1e27 / y;
    }
}

contract Witch {
    using RMath for uint256;
  
    uint256 constant public AUCTION_TIME = 4 * 60 * 60; // Time that auctions take to go to minimal price and stay there.
    ICauldron immutable public cauldron;
    ILadle immutable public ladle;

    constructor (ICauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

    // Put an undercollateralized vault up for liquidation.
    function grab(bytes12 vaultId)
        public
    {
        cauldron._grab(vaultId);
    }

    // Buy an amount of collateral off a vault in liquidation, paying at most `max` underlying.
    function buy(bytes12 vaultId, uint128 ink, uint128 max)
        public
    {
        // _slurp already checks that the vault is valid.
        uint128 art = price(vaultId, ink);                                                       // Cost of `price` | TODO: It would be cleaner to pass `timestamp` and `balances` as parameters to `price`
        require (art <= max, "Too expensive to buy");
        DataTypes.Balances memory balances = cauldron._slurp(vaultId, int128(ink), int128(art)); // Cost of `cauldron._slurp`  | Manipulate the vault | TODO: SafeCast
        ladle._join(vaultId, msg.sender, int128(ink), int128(art));                              // Cost of `ladle._join`      | Move the assets | TODO: SafeCast
        if (balances.art == 0 && balances.ink == 0) cauldron.destroy(vaultId);                   // Cost of `cauldron.destroy`
    }

    // Obtain the price in underlying terms to buy a selection of collateral from a vault in liquidation, at the preset time.
    function price(bytes12 vaultId, uint128 ink)
        public
        view
        returns (uint128)
    {
        // Let fail if the vault doesn't exist?
        // Let fail if the vault doesn't have the right asset?
        // Let fail if the vault doesn't have enough ink?
        uint32 timestamp = cauldron.timestamps(vaultId);                                    // 1 SLOAD + 700 + 12*16
        require (timestamp > 0, "Not for sale");
        DataTypes.Balances memory balances = cauldron.vaultBalances(vaultId);               // 1 SLOAD + 700 + 12*16
        uint128 _unit = unit(balances.art, uint32(block.timestamp) - timestamp);            // TODO: SafeCast
        uint128 _slice = ink * _unit;                                                       // Multiply collateral amount by the unit price. The result is the proportion of the debt that must be repaid in the vault.
        return _slice * balances.art;                                                       // Price in underlying terms.
    }

    /// Price of a collateral unit at the present moment
    //
    //                    1           1      min(auction, elapsed)
    // price = 1 / (------------- * (--- + -----------------------))
    //                   debt         2       2 * auction
    function unit(uint128 art, uint32 elapsed) public view returns (uint128) {
        uint256 RAY = 1e27;
        uint256 term1 = RAY / art;
        uint256 dividend3 = Math.min(AUCTION_TIME, block.timestamp - elapsed);
        uint256 divisor3 = AUCTION_TIME * 2;
        uint256 term2 = RAY / 2;
        uint256 term3 = dividend3 * RAY / divisor3;
        return uint128(RAY.rdiv(term1.rmul(term2 + term3)));                                // TODO: SafeCast
    }
}