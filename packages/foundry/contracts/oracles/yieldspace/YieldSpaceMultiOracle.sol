// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPoolOracle.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../interfaces/IOracle.sol";

contract YieldSpaceMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    error SourceNotFound(bytes32 baseId, bytes32 quoteId);

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        IPool indexed pool
    );

    struct Source {
        IPool pool;
        bool lending;
    }

    uint128 public constant ONE = 1e18;

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    IPoolOracle public immutable poolOracle;

    constructor(IPoolOracle _poolOracle) {
        poolOracle = _poolOracle;
    }

    /// @notice Set or reset a FYToken oracle source and its inverse
    /// @dev    PARAMETER ORDER IS CRUCIAL! If the ids are out of order the math will be wrong
    /// @param  seriesId FYToken id
    /// @param  baseId Underlying id
    /// @param  pool Pool where you can trade FYToken <-> underlying
    function setSource(
        bytes6 seriesId,
        bytes6 baseId,
        IPool pool
    ) external auth {
        // Initialise or update the TWAR observations
        poolOracle.updatePool(pool);

        sources[seriesId][baseId] = Source(pool, false);
        emit SourceSet(seriesId, baseId, pool);

        sources[baseId][seriesId] = Source(pool, true);
        emit SourceSet(baseId, seriesId, pool);
    }

    /// @inheritdoc IOracle
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view override returns (uint256 value, uint256 updateTime) {
        //solhint-disable-next-line not-rely-on-time
        if (base == quote) return (amount, block.timestamp);

        Source memory source = _source(base, quote);

        (value, updateTime) = source.lending
            ? poolOracle.peekSellBasePreview(source.pool, amount)
            : poolOracle.peekSellFYTokenPreview(source.pool, amount);
    }

    /// @inheritdoc IOracle
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external override returns (uint256 value, uint256 updateTime) {
        //solhint-disable-next-line not-rely-on-time
        updateTime = block.timestamp;

        if (base == quote) return (amount, updateTime);

        Source memory source = _source(base, quote);

        (value, updateTime) = source.lending
            ? poolOracle.getSellBasePreview(source.pool, amount)
            : poolOracle.getSellFYTokenPreview(source.pool, amount);
    }

    /// @dev Load the source for the base/quote and verify is valid
    /// @param base The asset in which the amount to be converted is represented
    /// @param quote The asset in which the converted value will be represented
    function _source(bytes32 base, bytes32 quote)
        internal
        view
        returns (Source memory source)
    {
        source = sources[base.b6()][quote.b6()];

        if (address(source.pool) == address(0)) {
            revert SourceNotFound(base, quote);
        }
    }
}
