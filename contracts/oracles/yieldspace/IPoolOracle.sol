// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

interface IPoolOracle {

    /// @notice returns the TWAR for a given `pool` using the moving average over the max available time range within the window
    /// @param pool Address of pool for which the observation is required
    /// @return twar The most up to date TWAR for `pool`
    function peek(address pool) external view returns (uint256 twar);

    /// @notice returns the TWAR for a given `pool` using the moving average over the max available time range within the window
    /// @dev will try to record a new observation if necessary, so equivalent to `update(pool); peek(pool);`
    /// @param pool Address of pool for which the observation is required
    /// @return twar The most up to date TWAR for `pool`
    function get(address pool) external returns (uint256 twar);

    /// @notice updates the cumulative ratio for the observation at the current timestamp. each observation is updated at most
    /// once per epoch period.
    /// @param pool Address of pool for which the observation should be recorded
    function update(address pool) external;
}
