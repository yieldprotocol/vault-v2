// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/vault-interfaces/IOracle.sol";
import "./CTokenInterface.sol";


contract CompoundRateOracle is IOracle {

    uint8 public constant override decimals = 1; // The Rate Oracle tracks an accumulator, and it makes no sense to talk of decimals

    address public immutable source;

    constructor(address source_) {
        source = source_;
    }

    /**
     * @notice Retrieve the latest value of the rate accumulator (borrowIndex).
     * @dev Note that the accumulator can decrease in certain situations like botched liquidations.
     */
    function _peek() private view returns (uint accumulator, uint updateTime) {
        accumulator = CTokenInterface(source).borrowIndex();
        require(accumulator > 0, "Compound rate is zero");
        updateTime = block.timestamp;
    }

    /**
     * @notice Retrieve the latest stored accumulator.
     */
    function peek(bytes32, bytes32, uint256)
        external view virtual override
        returns (uint256 accumulator, uint256 updateTime)
    {
        (accumulator, updateTime) = _peek();
    }

    /**
     * @notice Retrieve the value of the accumulator, updating it if necessary. Same as `peek` for this oracle.
     */
    function get(bytes32, bytes32, uint256)
        external virtual override
        returns (uint256 accumulator, uint256 updateTime)
    {
        (accumulator, updateTime) = _peek();
    }
}