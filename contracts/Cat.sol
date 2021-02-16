// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/IOracle.sol";
import "./interfaces/IVat.sol";
import "./libraries/DataTypes.sol";
import "./libraries/IlksPacking.sol";


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
    using IlksPacking for bytes1;
    using DecimalMath for uint256;
  
    uint256 constant public AUCTION_TIME; // Time that auctions take to go to minimal price and stay there.
    IVat immutable public vat;

    mapping (bytes6 => IOracle) oracles;                                               // [ilk] Spot oracles

    constructor (IVat vat_) {
        vat = vat_;
    }

    // Put an undercollateralized vault up for liquidation.
    function grab(bytes12 vault)
        public
    {
        vat._grab(vault);
    }

    // Buy an amount of collateral off a vault in liquidation, paying at most `max` underlying.
    function buy(bytes12 vault, bytes1 ilks, uint128[] memory inks, uint128 max)
        public
    {
        // _frob already checks that the vault is valid.
        int128 art = price(vault, ilks, inks);                                            // Cost of `price`
        require (art <= max, "Too expensive to buy");
        // TODO: Tweak `_frob` so that it takes the `art` from `msg.sender`, and sends the `ink` to him as well.
        DataTypes.Balances memory balances = vat._frob(vault, ilks, inks, art);                // Cost of `vat._frob`
        if (balances == 0) vat.destroy(vault);                                            // Cost of `vat.destroy`. Check debt and all balances.
    }

    // Obtain the price in underlying terms to buy a selection of collateral from a vault in liquidation, at the preset time.
    function price(bytes12 vault, bytes1 ilks, uint128[] memory inks)
        public
        view
        returns (int128)
    {
        // Let fail if the vault doesn't exist?
        // Let fail if the vault doesn't have the right ilk?
        // Let fail if the vault doesn't have enough ink?
        uint32 timestamp = vat.timestamps(vault);                          // 1 SLOAD + 700 + 12*16
        require (timestamp > 0, "Not for sale");
        DataTypes.Ilks memory vaultIlks = vat.vaultIlks(vault);                 // 1 SLOAD + 700 + 12*16. Maybe not needed.
        bytes6[] memory selectedIlks = ilks.identifiers(vaultIlks);
        DataTypes.Balances memory balances = vat.vaultBalances(vault);          // 3 SLOAD + 700 + 12*16. Maybe only 1 SLOAD needed.
        uint128[] memory _weights = weights(selectedIlks);
        uint128 _unit = unit(balances.debt, block.timestamp - timestamp);
        uint128 _slice;
        for (uint256 ilk = 0; ilk < selectedIlks.length; ilk++) {
            _slice += inks[ilk] * _weights[ilk] * _unit;                  // Normalize each collateral amount, and then multiply by the unit price. The result is the proportion of the debt that must be repaid in the vault.
        }
        return _slice * balances.debt;                                    // Price in underlying terms.
    }

    // Obtain the collateral normalization factors by dividing the spot price vs. ETH of each ilk, divided by the sum of all spot prices.
    function weights(bytes6[] memory ilks)
        public
        view
        returns (uint128[] memory)
    {
        uint128[] memory spots;
        uint128 total;
        for (uint256 ilk = 0; ilk < ilks.length; ilk++) {
            uint256 _spot = oracles[ilk].spot();
            spots.push(_spot);                             // C * Cost of `oracle.spot`
            total += _spot;
        }
        
        uint128[] memory _weights;
        for (uint256 ilk = 0; ilk < ilks[5]; ilk++) {
            _weights.push(spots[ilk] / total);
        }
        return _weights;
    }

    /// Price of a normalized collateral unit at the present moment
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