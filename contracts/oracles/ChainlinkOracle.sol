// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@yield-protocol/vault-interfaces/IOracle.sol";
import "./AggregatorV3Interface.sol";

/**
 * @title ChainlinkOracle
 */
contract ChainlinkOracle is IOracle {

    uint public constant SCALE_FACTOR = 1e10; // Since Chainlink has 8 dec places, and peek() needs 18

    address public immutable override source;

    constructor(address source_) {
        source = source_;
    }

    /**
     * @notice Retrieve the latest price of the price oracle.
     * @return price
     */
    function _peek() private view returns (uint price, uint updateTime) {
        int rawPrice;
        (, rawPrice,, updateTime,) = AggregatorV3Interface(source).latestRoundData();
        require(rawPrice > 0, "Chainlink price <= 0");
        price = uint(rawPrice) * SCALE_FACTOR;
    }

    /**
     * @notice Retrieve the latest price of the price oracle.
     * @return price
     */
    function peek() public virtual override view returns (uint price, uint updateTime) {
        (price, updateTime) = _peek();
    }

    /**
     * @notice Retrieve the latest price of the price oracle. Same as `peek` for this oracle.
     * @return price
     */
    function get() public virtual override returns (uint price, uint updateTime){
        (price, updateTime) = _peek();
    }
}
