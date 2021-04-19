// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@yield-protocol/vault-interfaces/IOracle.sol";
import "./CTokenInterface.sol";


contract CompoundChiOracle is IOracle {

    uint public constant SCALE_FACTOR = 1; // I think we don't need scaling for rate and chi oracles

    address public immutable override source;

    constructor(address source_) {
        source = source_;
    }

    /**
     * @notice Retrieve the latest price of the price oracle.
     * @return price
     */
    function _peek() private view returns (uint price, uint updateTime) {
        uint rawPrice = CTokenInterface(source).exchangeRateStored();
        require(rawPrice > 0, "Compound chi is zero");
        price = rawPrice * SCALE_FACTOR;
        updateTime = block.timestamp;
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