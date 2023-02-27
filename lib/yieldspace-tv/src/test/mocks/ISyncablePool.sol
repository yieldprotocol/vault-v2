// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

import {IPool} from "../../interfaces/IPool.sol";

/// Pool with sync() added for ease in manipulating reserves ratio during testing.
interface ISyncablePool is IPool {
    function sync() external;

    function mulMu(uint256 amount) external view returns (uint256);

    function calcRatioSeconds(
        uint128 fyTokenReserves,
        uint128 sharesReserves,
        uint256 secondsElapsed
    ) external view returns (uint256);
}
