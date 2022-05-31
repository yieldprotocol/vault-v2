// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import {IPool} from "@yield-protocol/yieldspace-interfaces/IPool.sol";
import {IPoolOracle} from "./IPoolOracle.sol";

/**
 * @title PoolOracle
 * @author Bruno Bonanno
 * @dev This contract collects data from different YieldSpace pools to compute a TWAR using a SMA (https://www.investopedia.com/terms/s/sma.asp)
 * Adapted from https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol
 */
//solhint-disable not-rely-on-time
contract PoolOracle is IPoolOracle {
    event ObservationRecorded(address indexed pool, uint256 index, Observation observation);

    error NoObservationsForPool(address pool);
    error MissingHistoricalObservation(address pool);
    error InsufficientElapsedTime(address pool, uint256 elapsedTime);

    struct Observation {
        uint256 timestamp;
        uint256 ratioCumulative;
    }

    // the desired amount of time over which the moving average should be computed, e.g. 24 hours
    uint256 public immutable windowSize;
    // the number of observations stored for each pool, i.e. how many ratio observations are stored for the window.
    // as granularity increases from 1, more frequent updates are needed, but moving averages become more precise.
    // averages are computed over intervals with sizes in the range:
    //   [windowSize - (windowSize / granularity) * 2, windowSize]
    // e.g. if the window size is 24 hours, and the granularity is 24, the oracle will return the TWAR for
    //   the period:
    //   [now - [22 hours, 24 hours], now]
    uint256 public immutable granularity;
    // this is redundant with granularity and windowSize, but stored for gas savings & informational purposes.
    uint256 public immutable periodSize;
    // this is to avoid using values that are too close in time to the current observation
    uint256 public immutable minTimeElapsed;

    // mapping from pool address to a list of ratio observations of that pool
    mapping(address => Observation[]) public poolObservations;

    constructor(
        uint256 windowSize_,
        uint256 granularity_,
        uint256 minTimeElapsed_
    ) {
        require(granularity_ > 1, "GRANULARITY");
        require((periodSize = windowSize_ / granularity_) * granularity_ == windowSize_, "WINDOW_NOT_EVENLY_DIVISIBLE");
        windowSize = windowSize_;
        granularity = granularity_;
        minTimeElapsed = minTimeElapsed_;
    }

    /// @dev calculates the index of the observation corresponding to the given timestamp
    /// @param timestamp The timestamp to calculate the index for
    /// @return index The index corresponding to the `timestamp`
    function observationIndexOf(uint256 timestamp) public view returns (uint256 index) {
        uint256 epochPeriod = timestamp / periodSize;
        return epochPeriod % granularity;
    }

    /// @dev returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    /// @param pool Address of pool for which the observation is required
    /// @return o The oldest observation available for `pool`
    function getOldestObservationInWindow(address pool) public view returns (Observation memory o) {
        uint256 length = poolObservations[pool].length;
        if (length == 0) {
            revert NoObservationsForPool(pool);
        }

        unchecked {
            uint256 observationIndex = observationIndexOf(block.timestamp);
            uint256 i;
            do {
                // can't possible overflow
                // compute the oldestObservation given `observationIndex`, basically `widowSize` in the past
                uint256 oldestObservationIndex = (++observationIndex) % granularity;

                // Read the oldet observation
                o = poolObservations[pool][oldestObservationIndex];

                // For an observation to be valid, it has to be newer than the `windowSize`            
                if (block.timestamp - o.timestamp < windowSize) {
                    return o;
                }

                // If the observation was not newer than the `windowSize` then we loop and try with the next one
                // We do this for 2 reasons
                //  a) The current slot may have never been updated due to low volume at the time, but the next may be.
                //     Finding a not-that-old observation (not strictly `windowTime` old) is better than aborting the whole tx
                //  b) We're within the first `windowTime` (i.e. 24hs) of this pool being in use by the oracle, 
                //     hence we don't have enough history for every slot to be valid, 
                //     so we loop hoping for the newer slots to have valid data

                ++i; // can't possible overflow
            } while (i < length);

            revert MissingHistoricalObservation(pool);
        }
    }

    // @inheritdoc IPoolOracle
    function update(address pool) public override {
        // populate the array with empty observations (oldest call only)
        // the first time ever that this method is called for a given `pool` we initialise its array of observations
        for (uint256 i = poolObservations[pool].length; i < granularity; i++) {
            poolObservations[pool].push();
        }

        // get the observation for the current period
        uint256 index = observationIndexOf(block.timestamp);
        Observation storage observation = poolObservations[pool][index];

        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint256 timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > periodSize) {
            observation.timestamp = block.timestamp;
            observation.ratioCumulative = _getCurrentCumulativeRatio(pool);
            emit ObservationRecorded(pool, index, observation);
        }
    }

    /// @inheritdoc IPoolOracle
    function peek(address pool) public view override returns (uint256 twar) {
        Observation memory oldestObservation = getOldestObservationInWindow(pool);

        uint256 timeElapsed = block.timestamp - oldestObservation.timestamp;

        // This check is to safeguard the edge case where the pool was initialised just now (or very, very recently)
        // and hence the TWAR can't be trusted as it would be easy to manipulate it.
        // This can happen cause even if we always try to use a value that's `windowSize` old, if said value is stale or invalid
        // we'll loop and try newere ones until we find a valid one (or we blow).
        if (timeElapsed < minTimeElapsed) {
            revert InsufficientElapsedTime(pool, timeElapsed);
        }

        // cumulative ratio is in (ratio * seconds) units so for the average we simply get it after division by time elapsed
        return ((_getCurrentCumulativeRatio(pool) - oldestObservation.ratioCumulative) * 1e18) / (timeElapsed * 1e27);
    }

    /// @inheritdoc IPoolOracle
    function get(address pool) external override returns (uint256 twar) {
        update(pool);
        return peek(pool);
    }

    function _getCurrentCumulativeRatio(address pool) internal view returns (uint256 lastRatio) {
        lastRatio = IPool(pool).cumulativeBalancesRatio();
        (uint256 baseCached, uint256 fyTokenCached, uint256 blockTimestampLast) = IPool(pool).getCache();
        if (block.timestamp != blockTimestampLast) {
            lastRatio += ((fyTokenCached * 1e27 * (block.timestamp - blockTimestampLast)) / baseCached);
        }
    }
}
