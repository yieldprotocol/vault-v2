// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "../../constants/Constants.sol";
import "./CTokenInterface.sol";


contract CompoundMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed kind, address indexed source);

    mapping(bytes6 => mapping(bytes6 => address)) public sources;

    /**
     * @notice Set or reset a source
     */
    function setSource(bytes6 base, bytes6 kind, address source) external auth {
        sources[base][kind] = source;
        emit SourceSet(base, kind, source);
    }

    /**
     * @notice Retrieve the latest stored accumulator.
     */
    function peek(bytes32 base, bytes32 kind, uint256)
        external view virtual override
        returns (uint256 accumulator, uint256 updateTime)
    {
        (accumulator, updateTime) = _peek(base.b6(), kind.b6());
    }

    /**
     * @notice Retrieve the latest accumulator from source, updating it if necessary.
     */
    function get(bytes32 base, bytes32 kind, uint256)
        external virtual override
        returns (uint256 accumulator, uint256 updateTime)
    {
        (accumulator, updateTime) = _peek(base.b6(), kind.b6());
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function _peek(bytes6 base, bytes6 kind) private view returns (uint accumulator, uint updateTime) {
        address source = sources[base][kind];
        require (source != address(0), "Source not found");

        if (kind == RATE.b6()) accumulator = CTokenInterface(source).borrowIndex();
        else if (kind == CHI.b6()) accumulator = CTokenInterface(source).exchangeRateStored();
        else revert("Unknown oracle type");

        require(accumulator > 0, "Compound accumulator is zero");

        updateTime = block.timestamp;
    }
}