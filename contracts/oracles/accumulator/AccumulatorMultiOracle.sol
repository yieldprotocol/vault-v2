// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import '@yield-protocol/utils-v2/contracts/access/AccessControl.sol';
import '@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol';
import '@yield-protocol/utils-v2/contracts/math/WPow.sol';
import '@yield-protocol/vault-interfaces/IOracle.sol';

import '../../constants/Constants.sol';

/**
A collection of independent Accumulator Oracles

Each Accumulator is simple: it starts when `setSource` is called, 
and each `get` call returns accumulationRate ^ (time in seconds since oracle creation)
 */
contract AccumulatorMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;
    using WPow for uint256;

    struct Accumulator {
        // @dev secondly rate
        uint256 accumulationRate;
        // @dev rate accumulated so far - check `get` for details
        uint256 currentRate;
        // time when `currentRate` was last updated
        uint256 lastUpdated;
    }

    mapping(bytes6 => mapping(bytes6 => Accumulator)) public sources;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed kind, uint256 startRate, uint256 accumulationRate);
    event AccumulationRateUpdated(bytes6 indexed baseId, bytes6 indexed kind, uint256 accumulationRate);

    /**
    @notice Set a source
    @param baseId: base to set the source for
    @param kindId: kind of oracle (example: chi/rate)
    @param startRate: rate the oracle starts with
    @param accumulationRate: secondly rate
     */
    function setSource(
        bytes6 baseId,
        bytes6 kindId,
        uint256 startRate,
        uint256 accumulationRate
    ) external auth {
        Accumulator memory source = sources[baseId][kindId];
        require(source.currentRate == 0, "Source's already set");

        sources[baseId][kindId] = Accumulator({
            accumulationRate: accumulationRate,
            currentRate: startRate,
            lastUpdated: block.timestamp
        });
        emit SourceSet(baseId, kindId, startRate, accumulationRate);
    }

    /**
    @notice Updates accumulation rate
    
    The accumulation rate can only be updated on an up-to-date oracle: get() was called in the
    same block. See get() for more details
     */
    function updateAccumulationRate(
        bytes6 baseId,
        bytes6 kindId,
        uint256 accumulationRate
    ) external auth {
        Accumulator memory source = sources[baseId][kindId];
        require(source.currentRate != 0, 'Source not found');

        require(source.lastUpdated == block.timestamp, 'stale accumulator');
        sources[baseId][kindId].accumulationRate = accumulationRate;

        emit AccumulationRateUpdated(baseId, kindId, accumulationRate);
    }

    /**
     * @notice Retrieve the latest stored accumulator.
     */
    function peek(
        bytes32 base,
        bytes32 kind,
        uint256
    ) external view virtual override returns (uint256 accumulator, uint256 updateTime) {
        Accumulator memory source = sources[base.b6()][kind.b6()];
        require(source.currentRate != 0, 'Source not found');

        accumulator = source.currentRate;
        require(accumulator > 0, 'Accumulator is zero');

        updateTime = block.timestamp;
    }

    /**
    @notice Retrieve the latest accumulator from source, updating it if necessary.

    Computes baseRate ^ (block.timestamp - creation timestamp)

    pow() is not O(1), so the naive implementation will become slower as the time passes
    To workaround that, each time get() is called, we:
        1) compute the return value
        2) store the return value in `currentRate` field, update lastUpdated timestamp

    Becase we have `currentRate`, step 1 becomes `currentRate * baseRate ^ (block.timestamp - lastUpdated)
     */
    function get(
        bytes32 base,
        bytes32 kind,
        uint256
    ) external virtual override returns (uint256 accumulator, uint256 updateTime) {
        Accumulator memory state = sources[base.b6()][kind.b6()];
        require(state.currentRate != 0, 'Source not found');

        uint256 cycles = (block.timestamp - state.lastUpdated);
        state.currentRate *= state.accumulationRate.wpow(cycles);
        state.currentRate /= 1e18;
        state.lastUpdated = block.timestamp;

        accumulator = state.currentRate;
        require(accumulator > 0, 'Accumulator is zero');

        sources[base.b6()][kind.b6()] = state;

        updateTime = block.timestamp;
    }
}
