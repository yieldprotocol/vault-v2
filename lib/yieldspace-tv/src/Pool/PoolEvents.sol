// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

/* POOL EVENTS
 ******************************************************************************************************************/

abstract contract PoolEvents {
    /// Fees have been updated.
    event FeesSet(uint16 g1Fee);

    /// Pool is matured and all LP tokens burned. gg.
    event gg();

    /// gm.  Pool is initialized.
    event gm();

    /// A liquidity event has occured (burn / mint).
    event Liquidity(
        uint32 maturity,
        address indexed from,
        address indexed to,
        address indexed fyTokenTo,
        int256 base,
        int256 fyTokens,
        int256 poolTokens
    );

    /// The _update fn has run and cached balances updated.
    event Sync(uint112 baseCached, uint112 fyTokenCached, uint256 cumulativeBalancesRatio);

    /// One of the four trading functions has been called:
    /// - buyBase
    /// - sellBase
    /// - buyFYToken
    /// - sellFYToken
    event Trade(uint32 maturity, address indexed from, address indexed to, int256 base, int256 fyTokens);
}
