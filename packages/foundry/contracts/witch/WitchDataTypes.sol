// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library WitchDataTypes {
    struct Auction {
        address owner;
        uint32 start;
        bytes6 baseId; // We cache the baseId here
        uint128 ink;
        uint128 art;
        address auctioneer;
    }

    struct Line {
        uint32 duration; // Time that auctions take to go to minimal price and stay there
        uint64 proportion; // Proportion of the vault that is available each auction (1e18 = 100%)
        uint64 initialOffer; // Proportion of collateral that is sold at auction start (1e18 = 100%)
    }

    struct Limits {
        uint128 max; // Maximum concurrent auctioned collateral
        uint128 sum; // Current concurrent auctioned collateral
    }
}
