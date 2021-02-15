// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/IOracle.sol";
import "./interfaces/IVat.sol";
import "./libraries/IlksPacking.sol";


contract Cat {
    using IlksPacking for bytes6[5];
  
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
        IVat.Balances memory balances = vat._frob(vault, ilks, inks, art);                // Cost of `vat._frob`
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
        IVat.Ilks memory vaultIlks = vat.vaultIlks(vault);                 // 1 SLOAD + 700 + 12*16. Maybe not needed.
        bytes6[6] selectedIlks = vaultIlks.select(ilks);
        IVat.Balances memory balances = vat.vaultBalances(vault);          // 3 SLOAD + 700 + 12*16. Maybe only 1 SLOAD needed.
        uint128[6] _weights = weights(selectedIlks);
        uint128 _unit = unit(balances.debt, block.timestamp - timestamp);
        uint128 _slice;
        for (uint256 ilk = 0; ilk < selectedIlks[5]; ilk++) {
            _slice += inks[ilk] * _weights[ilk] * _unit;                  // Normalize each collateral amount, and then multiply by the unit price. The result is the proportion of the debt that must be repaid in the vault.
        }
        return _slice * balances.debt;                                    // Price in underlying terms.
    }

    // Obtain the collateral normalization factors by dividing the spot price vs. ETH of each ilk, divided by the sum of all spot prices.
    function weights(bytes6[6] ilks)
        public
        view
        returns (uint128[6])
    {
        uint128[6] spots;
        for (uint256 ilk = 0; ilk < ilks[5]; ilk++) {
            spots[ilk] = oracles[ilk].spot();                             // C * Cost of `oracle.spot`
        }
        uint128 total;
        for (uint256 ilk = 0; ilk < ilks[5]; ilk++) {
            total += spots[ilk];
        }
        uint128[6] _weights;
        for (uint256 ilk = 0; ilk < ilks[5]; ilk++) {
            _weights[ilk] = spots[ilk] / total;
        }
        return _weights;
    }

    /// Price of a normalized collateral unit at the present moment
    //
    //                    1           1      min(auction, elapsed)
    // price = 1 / (------------- * (--- + -----------------------))
    //                   debt         2       2 * auction
    function unit(uint128 art, uint32 elapsed) public view returns (uint256) {
        uint256 term1 = UNIT.div(art);
        uint256 dividend3 = Math.min(AUCTION_TIME, block.timestamp - elapsed); // - unlikely to overflow
        uint256 divisor3 = AUCTION_TIME.mul(2);
        uint256 term2 = UNIT.div(2);
        uint256 term3 = dividend3.mul(UNIT).div(divisor3);
        return divd(UNIT, muld(term1, term2 + term3)); // + unlikely to overflow
    }
}