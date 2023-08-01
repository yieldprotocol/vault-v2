// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "../ISourceMock.sol";
import "./OffchainAggregatorMock.sol";


contract ChainlinkAggregatorV3Mock is ISourceMock {
    int public price;   // Prices in Chainlink can be negative (!)
    uint public timestamp;
    uint8 public decimals = 18;  // Decimals provided in the oracle prices
    address public aggregator;

    constructor() {
        aggregator = address(new OffchainAggregatorMock());
    }

    function set(uint price_) external override {// We provide prices with 18 decimals, which will be scaled Chainlink's decimals
        price = int(price_);
        timestamp = block.timestamp;
    }


    function setTimestamp(uint timestamp_) external {// Set timestamp for testing
        timestamp = timestamp_;
    }

    function setAggregator(address aggregator_) external {
        aggregator = aggregator_;
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, timestamp, 0);
    }
}
