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
        bytes6 ilkId;
    }

    struct Balances {
        uint128 art;                                                     // Debt
        uint128 ink;                                                     // Assets
    }
}