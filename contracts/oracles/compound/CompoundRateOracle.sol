// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@yield-protocol/vault-interfaces/IOracle.sol";
import "./CTokenInterface.sol";


contract CompoundRateOracle is IOracle {

    uint public constant SCALE_FACTOR = 1; // I think we don't need scaling for rate and chi oracles

    address public immutable source;

    constructor(address source_) {
        source = source_;
    }

    /**
     * @notice Retrieve the latest price of the price oracle.
     * @return price
     */
    function _peek() private view returns (uint price, uint updateTime) {
        uint rawPrice = CTokenInterface(source).borrowIndex();
        require(rawPrice > 0, "Compound rate is zero");
        price = rawPrice * SCALE_FACTOR;
        updateTime = block.timestamp;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * @return value
     */
    function peek(bytes32, bytes32, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        uint256 price;
        (price, updateTime) = _peek();
        value = price * amount / 1e18;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     * @return value
     */
    function get(bytes32, bytes32, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        uint256 price;
        (price, updateTime) = _peek();
        value = price * amount / 1e18;
    }
}