// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IOracle {

    /**
     * @notice The original source for the date
     * @return The address of the original source
     */
    function source() external view returns (address);

    /**
     * @notice Doesn't refresh the price, but returns the latest value available without doing any transactional operations:
     * eg, the price cached by the most recent call to `get()`.
     * @return value in wei
     */
    function peek(uint256 amount) external view returns (uint256 value, uint256 updateTime);

    /**
     * @notice Does whatever work or queries will yield the most up-to-date price, and returns it (typically also caching it
     * for `peek()` callers).
     * @return value in wei
     */
    function get(uint256 amount) external returns (uint256 value, uint256 updateTime);
}
