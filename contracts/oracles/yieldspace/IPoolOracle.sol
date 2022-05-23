// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

interface IPoolOracle {
    // returns the TWAR for a given pool using the moving average over the max available time range within the window
    function peek(address pool) external view returns (uint256 twar);

    // updates the oracle if necessary and
    // returns the TWAR for a given pool using the moving average over the max available time range within the window
    function get(address pool) external returns (uint256 twar);
}
