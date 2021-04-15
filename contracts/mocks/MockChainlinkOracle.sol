// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./OracleMock.sol";
import "../oracles/ChainlinkOracle.sol";

/**
 * @title MockChainlinkOracle
 * @author Jacob Eliosoff (@jacob-eliosoff)
 * @notice A ChainlinkOracle whose price we can override.  Testing purposes only!
 */
contract MockChainlinkOracle is ChainlinkOracle, OracleMock {
    constructor(AggregatorV3Interface aggregator_) ChainlinkOracle(aggregator_) {}

    function get() public override(ChainlinkOracle, OracleMock) returns (uint price, uint updateTime) {
        (price, updateTime) = (spot != 0) ? (spot, updated) : super.get();
    }

    function peek() public override(ChainlinkOracle, OracleMock) view returns (uint price, uint updateTime) {
        (price, updateTime) = (spot != 0) ? (spot, updated) : super.peek();
    }
}
