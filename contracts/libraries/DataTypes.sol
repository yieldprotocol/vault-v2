pragma solidity ^0.8.0;


library DataTypes {
    struct Series {
        address fyToken;                                               // Redeemable token for the series.
        uint32  maturity;                                              // Unix time at which redemption becomes possible.
        bytes6  base;                                                  // Token received on redemption.
        // bytes2 free
    }

    // ==== Vault ordering ====
    struct Vault {
        address owner;
        bytes6 series;                                                 // Each vault is related to only one series, which also determines the underlying.
        // 6 bytes free
    }

    // ==== Vault composition ====
    struct Ilks {
        bytes6[5] ids;
        bytes2 length;
    }

    struct Balances {
        uint128 debt;
        uint128[5] assets;
    }
}