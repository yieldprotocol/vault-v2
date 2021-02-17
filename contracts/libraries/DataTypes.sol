pragma solidity ^0.8.0;
import "../interfaces/IFYToken.sol";

library DataTypes {
    struct Series {
        IFYToken fyToken;                                               // Redeemable token for the series.
        bytes6  baseId;                                                  // Token received on redemption.
        uint32  maturity;                                              // Unix time at which redemption becomes possible.
        // bytes2 free
    }

    // ==== Vault ordering ====
    struct Vault {
        address owner;
        bytes6 seriesId;                                                 // Each vault is related to only one series, which also determines the underlying.
        // 6 bytes free
    }

    // ==== Vault composition ====
    struct Ilks {
        bytes6[5] ilkIds;
        bytes2 length;
    }

    struct Balances {
        uint128 debt;
        uint128[5] assets;
    }
}