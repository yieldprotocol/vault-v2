// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/math/WPow.sol";
import "@yield-protocol/vault-interfaces/src/IOracle.sol";

import "../../constants/Constants.sol";

/**
A collection of independent Accumulator Oracles

Each Accumulator is simple: it starts when `setSource` is called, 
and each `get` call returns perSecondRate ^ (time in seconds since oracle creation)
 */
contract AccumulatorMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;
    using WPow for uint256;

    struct Accumulator {
        /// @dev secondly rate
        uint256 perSecondRate;
        /// @dev rate accumulated so far - check `get` for details
        uint256 accumulated;
        /// @dev time when `accumulated` was last updated
        uint256 lastUpdated;
    }

    mapping(bytes6 => mapping(bytes6 => Accumulator)) public sources;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed kind, uint256 startRate, uint256 perSecondRate);
    event PerSecondRateUpdated(bytes6 indexed baseId, bytes6 indexed kind, uint256 perSecondRate);

    /**
    @notice Set a source
    @param baseId: base to set the source for
    @param kindId: kind of oracle (example: chi/rate)
    @param startRate: rate the oracle starts with
    @param perSecondRate: secondly rate
     */
    function setSource(
        bytes6 baseId,
        bytes6 kindId,
        uint256 startRate,
        uint256 perSecondRate
    ) external auth {
        Accumulator memory source = sources[baseId][kindId];
        require(source.accumulated == 0, "Source is already set");

        sources[baseId][kindId] = Accumulator({
            perSecondRate: perSecondRate,
            accumulated: startRate,
            lastUpdated: block.timestamp
        });
        emit SourceSet(baseId, kindId, startRate, perSecondRate);
    }

    /**
    @notice Updates accumulation rate
    
    The accumulation rate can only be updated on an up-to-date oracle: get() was called in the
    same block. See get() for more details
     */
    function updatePerSecondRate(
        bytes6 baseId,
        bytes6 kindId,
        uint256 perSecondRate
    ) external auth {
        Accumulator memory source = sources[baseId][kindId];
        require(source.accumulated != 0, "Source not found");

        require(source.lastUpdated == block.timestamp, "stale accumulator");
        sources[baseId][kindId].perSecondRate = perSecondRate;

        emit PerSecondRateUpdated(baseId, kindId, perSecondRate);
    }

    /**
     * @notice Retrieve the latest stored accumulated rate.
     */
    function peek(
        bytes32 base,
        bytes32 kind,
        uint256
    ) external view virtual override returns (uint256 accumulated, uint256 updateTime) {
        Accumulator memory source = sources[base.b6()][kind.b6()];
        require(source.accumulated != 0, "Source not found");

        accumulated = source.accumulated;
        require(accumulated > 0, "Accumulated rate is zero");

        updateTime = block.timestamp;
    }

    /**
    @notice Retrieve the latest accumulated rate from source, updating it if necessary.

    Computes baseRate ^ (block.timestamp - creation timestamp)

    pow() is not O(1), so the naive implementation will become slower as the time passes
    To workaround that, each time get() is called, we:
        1) compute the return value
        2) store the return value in `accumulated` field, update lastUpdated timestamp

    Becase we have `accumulated`, step 1 becomes `accumulated * baseRate ^ (block.timestamp - lastUpdated)
     */
    function get(
        bytes32 base,
        bytes32 kind,
        uint256
    ) external virtual override returns (uint256 accumulated, uint256 updateTime) {
        Accumulator memory accumulator = sources[base.b6()][kind.b6()];
        require(accumulator.accumulated != 0, "Source not found");

        uint256 secondsSinceLastUpdate = (block.timestamp - accumulator.lastUpdated);
        if (secondsSinceLastUpdate > 0) {
            accumulator.accumulated *= accumulator.perSecondRate.wpow(secondsSinceLastUpdate);
            accumulator.accumulated /= 1e18;
            accumulator.lastUpdated = block.timestamp;

            sources[base.b6()][kind.b6()] = accumulator;
        }

        accumulated = accumulator.accumulated;
        require(accumulated > 0, "Accumulated rate is zero");
        updateTime = block.timestamp;
    }
}
