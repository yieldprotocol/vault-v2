// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import "./IPool.sol";

interface IPoolOracle {
    /// @notice returns the TWAR for a given `pool` using the moving average over the max available time range within the window
    /// @param pool Address of pool for which the observation is required
    /// @return twar The most up to date TWAR for `pool`
    function peek(IPool pool) external view returns (uint256 twar);

    /// @notice returns the TWAR for a given `pool` using the moving average over the max available time range within the window
    /// @dev will try to record a new observation if necessary, so equivalent to `update(pool); peek(pool);`
    /// @param pool Address of pool for which the observation is required
    /// @return twar The most up to date TWAR for `pool`
    function get(IPool pool) external returns (uint256 twar);

    /// @notice updates the cumulative ratio for the observation at the current timestamp. Each observation is updated at most
    /// once per epoch period.
    /// @param pool Address of pool for which the observation should be recorded
    /// @return updated Flag to indicate if the observation at the current timestamp was actually updated
    function updatePool(IPool pool) external returns(bool updated);

    /// @notice updates the cumulative ratio for the observation at the current timestamp. Each observation is updated at most
    /// once per epoch period.
    /// @param pools Addresses of pool for which the observation should be recorded
    function updatePools(IPool[] calldata pools) external;

    /// Returns how much fyToken would be required to buy `baseOut` base.
    /// @notice This function will also record a new snapshot on the oracle if necessary,
    /// so it's the preferred one, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param baseOut Amount of base hypothetically desired.
    /// @return fyTokenIn Amount of fyToken hypothetically required.
    /// @return updateTime Timestamp for when this price was calculated.
    function getBuyBasePreview(IPool pool, uint256 baseOut) external returns (uint256 fyTokenIn, uint256 updateTime);

    /// Returns how much base would be required to buy `fyTokenOut`.
    /// @notice This function will also record a new snapshot on the oracle if necessary,
    /// so it's the preferred one, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param fyTokenOut Amount of fyToken hypothetically desired.
    /// @return baseIn Amount of base hypothetically required.
    /// @return updateTime Timestamp for when this price was calculated.
    function getBuyFYTokenPreview(IPool pool, uint256 fyTokenOut) external returns (uint256 baseIn, uint256 updateTime);

    /// Returns how much fyToken would be obtained by selling `baseIn`.
    /// @notice This function will also record a new snapshot on the oracle if necessary,
    /// so it's the preferred one, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param baseIn Amount of base hypothetically sold.
    /// @return fyTokenOut Amount of fyToken hypothetically bought.
    /// @return updateTime Timestamp for when this price was calculated.
    function getSellBasePreview(IPool pool, uint256 baseIn) external returns (uint256 fyTokenOut, uint256 updateTime);

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @notice This function will also record a new snapshot on the oracle if necessary,
    /// so it's the preferred one, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return baseOut Amount of base hypothetically bought.
    /// @return updateTime Timestamp for when this price was calculated.
    function getSellFYTokenPreview(IPool pool, uint256 fyTokenIn)
        external
        returns (uint256 baseOut, uint256 updateTime);

    /// Returns how much fyToken would be required to buy `baseOut` base.
    /// @notice This function is view and hence it will not try to update the oracle
    /// so it should be avoided when possible, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param baseOut Amount of base hypothetically desired.
    /// @return fyTokenIn Amount of fyToken hypothetically required.
    /// @return updateTime Timestamp for when this price was calculated.
    function peekBuyBasePreview(IPool pool, uint256 baseOut) external view returns (uint256 fyTokenIn, uint256 updateTime);

    /// Returns how much base would be required to buy `fyTokenOut`.
    /// @notice This function is view and hence it will not try to update the oracle
    /// so it should be avoided when possible, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param fyTokenOut Amount of fyToken hypothetically desired.
    /// @return baseIn Amount of base hypothetically required.
    /// @return updateTime Timestamp for when this price was calculated.
    function peekBuyFYTokenPreview(IPool pool, uint256 fyTokenOut)
        external view
        returns (uint256 baseIn, uint256 updateTime);

    /// Returns how much fyToken would be obtained by selling `baseIn`.
    /// @notice This function is view and hence it will not try to update the oracle
    /// so it should be avoided when possible, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param baseIn Amount of base hypothetically sold.
    /// @return fyTokenOut Amount of fyToken hypothetically bought.
    /// @return updateTime Timestamp for when this price was calculated.
    function peekSellBasePreview(IPool pool, uint256 baseIn) external view returns (uint256 fyTokenOut, uint256 updateTime);

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @notice This function is view and hence it will not try to update the oracle
    /// so it should be avoided when possible, as if the oracle doesn't get updated periodically, it'll stop working
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return baseOut Amount of base hypothetically bought.
    /// @return updateTime Timestamp for when this price was calculated.
    function peekSellFYTokenPreview(IPool pool, uint256 fyTokenIn)
        external view
        returns (uint256 baseOut, uint256 updateTime);
}
