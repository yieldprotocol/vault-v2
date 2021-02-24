// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/IOracle.sol";
import "./interfaces/ICauldron.sol";
import "./libraries/DataTypes.sol";


library Math {
    /// @dev Minimum of two unsigned integers
    function min(uint256 x, uint256 y) external pure returns (uint256) {
        return x < y ? x : y;
    }

    /// @dev Maximum of two unsigned integers
    function max(uint256 x, uint256 y) external pure returns (uint256) {
        return x > y ? x : y;
    }
}

library DecimalMath {
    /// @dev Units used for fixed point arithmetic
    function UNIT() external pure returns (uint256) {
        return 1e27;
    }

    /// @dev Multiply x and y, with y being fixed point. Rounds down.
    function muld(uint256 x, uint256 y) external pure returns (uint256) {
        return x * y / 1e27;
    }

    /// @dev Divide x and y, with y being fixed point. Rounds down.
    function divd(uint256 x, uint256 y) external pure returns (uint256) {
        return x * 1e27 / y;
    }
}

contract Cat {
    using DecimalMath for uint256;
  
    uint256 constant public AUCTION_TIME; // Time that auctions take to go to minimal price and stay there.
    ICauldron immutable public cauldron;

    mapping (bytes6 => IOracle) oracles;                                                // [asset] Spot oracles

    constructor (ICauldron cauldron_) {
        cauldron = cauldron_;
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
        // _stir already checks that the vault is valid.
        int128 art = price(vaultId, ink);                                               // Cost of `price`
        require (art <= max, "Too expensive to buy");
        // TODO: Tweak `_stir` so that it takes the `art` from `msg.sender`, and sends the `ink` to him as well.
        DataTypes.Balances memory balances = cauldron._stir(vault, ink, art);                // Cost of `cauldron._stir`
        if (bytes32(balances) == bytes32(0)) cauldron.destroy(vault);                        // Cost of `cauldron.destroy`. Check balances.
    }

    // Obtain the price in underlying terms to buy a selection of collateral from a vault in liquidation, at the preset time.
    function price(bytes12 vaultId, uint128 ink)
        public
        view
        returns (int128)
    {
        // Let fail if the vault doesn't exist?
        // Let fail if the vault doesn't have the right asset?
        // Let fail if the vault doesn't have enough ink?
        uint32 timestamp = cauldron.timestamps(vaultId);                                     // 1 SLOAD + 700 + 12*16
        require (timestamp > 0, "Not for sale");
        DataTypes.Balances memory balances = cauldron.vaultBalances(vaultId);                // 1 SLOAD + 700 + 12*16
        uint128 _unit = unit(balances.art, block.timestamp - timestamp);
        uint128 _slice = balances.ink * _unit;                                          // Multiply collateral amount by the unit price. The result is the proportion of the debt that must be repaid in the vault.
        return _slice * balances.art;                                                   // Price in underlying terms.
    }

    /// Price of a collateral unit at the present moment
    //
    //                    1           1      min(auction, elapsed)
    // price = 1 / (------------- * (--- + -----------------------))
    //                   debt         2       2 * auction
    function unit(uint128 art, uint32 elapsed) public view returns (uint256) {
        uint256 UNIT = DecimalMath.UNIT();
        uint256 term1 = UNIT / art;
        uint256 dividend3 = Math.min(AUCTION_TIME, block.timestamp - elapsed);
        uint256 divisor3 = AUCTION_TIME * 2;
        uint256 term2 = UNIT / 2;
        uint256 term3 = dividend3 * UNIT / divisor3;
        return UNIT.divd(term1.muld(term2 + term3));
    }
}