// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "./ChainlinkAggregatorV3Mock.sol";

/**
ChainlinkAggregatorV3Mock but with configurable decimals
 */
contract ChainlinkAggregatorV3MockEx is ChainlinkAggregatorV3Mock {
    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}
