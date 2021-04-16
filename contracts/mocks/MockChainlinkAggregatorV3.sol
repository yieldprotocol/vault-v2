// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

contract MockChainlinkAggregatorV3 {
    int public price;
    uint public timestamp;

    function set(int price_) external {
        price = price_ / 1e10;          // Provide prices with 18 decimals, which will be scaled down to Chainlink's 8
        timestamp = block.timestamp;
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, timestamp, 0);
    }
}
