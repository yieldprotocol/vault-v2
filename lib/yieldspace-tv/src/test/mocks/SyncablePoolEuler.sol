// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

import {PoolEuler} from "../../Pool/Modules/PoolEuler.sol";
import {ISyncablePool} from "./ISyncablePool.sol";

/// Pool with sync() added for ease in manipulating reserves ratio during testing.
contract SyncablePoolEuler is PoolEuler, ISyncablePool {
    constructor(
        address euler_, // The main Euler contract address
        address shares_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) PoolEuler(euler_, shares_, fyToken_, ts_, g1Fee_) {}

    /// Updates the cache to match the actual balances.  Useful for testing.  Risky for prod.
    function sync() public {
        _update(_getSharesBalance(), _getFYTokenBalance(), sharesCached, fyTokenCached);
    }

    function getSharesSurplus() public view returns (uint128) {
        return _getSharesBalance() - sharesCached;
    }

    function mulMu(uint256 amount) external view returns (uint256) {
        return _mulMu(amount);
    }

    function calcRatioSeconds(
        uint128 fyTokenReserves,
        uint128 sharesReserves,
        uint256 secondsElapsed
    ) public view returns (uint256) {
        return (uint256(fyTokenReserves) * 1e27 * secondsElapsed) / _mulMu(sharesReserves);
    }
}
