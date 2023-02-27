// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

import "../interfaces/IPoolOracle.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";

/**
 * @title PoolOracle
 * @author Bruno Bonanno
 * @dev This contract collects data from different YieldSpace pools to compute a TWAR using a SMA (https://www.investopedia.com/terms/s/sma.asp)
 * Adapted from https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol
 */
//solhint-disable not-rely-on-time
contract PoolOracle is IPoolOracle {
    using Math64x64 for *;
    using Exp64x64 for *;

    event ObservationRecorded(IPool indexed pool, uint256 index, Observation observation);

    error NoObservationsForPool(IPool pool);
    error MissingHistoricalObservation(IPool pool);
    error InsufficientElapsedTime(IPool pool, uint256 elapsedTime);

    struct Observation {
        uint256 timestamp;
        uint256 ratioCumulative;
    }

    uint128 public constant WAD = 1e18;
    uint128 public constant RAY = 1e27;

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
    mapping(IPool => Observation[]) public poolObservations;

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

    /// @notice calculates the index of the observation corresponding to the given timestamp
    /// @param timestamp The timestamp to calculate the index for
    /// @return index The index corresponding to the `timestamp`
    function observationIndexOf(uint256 timestamp) public view returns (uint256 index) {
        uint256 epochPeriod = timestamp / periodSize;
        index = epochPeriod % granularity;
    }

    /// @notice returns the oldest observation available, starting at the oldest epoch (at the beginning of the window) relative to the current time
    /// @param pool Address of pool for which the observation is required
    /// @return o The oldest observation available for `pool`
    function getOldestObservationInWindow(IPool pool) public view returns (Observation memory o) {
        uint256 length = poolObservations[pool].length;
        if (length == 0) {
            revert NoObservationsForPool(pool);
        }

        unchecked {
            uint256 observationIndex = observationIndexOf(block.timestamp);
            for (uint256 i; i < length; ) {
                // can't possible overflow
                // compute the oldestObservation given `observationIndex`, basically `widowSize` in the past
                uint256 oldestObservationIndex = (++observationIndex) % granularity;

                // Read the oldest observation
                o = poolObservations[pool][oldestObservationIndex];

                // For an observation to be valid, it has to be newer than the `windowSize`
                if (block.timestamp - o.timestamp < windowSize) {
                    return o;
                }

                // If the observation was not newer than the `windowSize` then we loop and try with the next one
                // We do this for 2 reasons
                //  a) The current slot may have never been updated due to low volume at the time, but the next one may have been.
                //     Finding a not-that-old observation (not strictly `windowTime` old) is better than aborting the whole tx
                //  b) We could be within the first `windowTime` (i.e. 24hs) of this pool being in use by the oracle,
                //     hence we don't have enough history for every slot to be valid,
                //     so we loop hoping for the newer slots to have valid data

                ++i; // can't possible overflow
            }

            revert MissingHistoricalObservation(pool);
        }
    }

    // @inheritdoc IPoolOracle
    function updatePool(IPool pool) public override returns(bool updated) {
        // populate the array with empty observations (only on the first call ever for each pool)
        unchecked {
            for (uint256 i = poolObservations[pool].length; i < granularity; ) {
                poolObservations[pool].push();
                ++i;
            }
        }

        // get the observation for the current period
        uint256 index = observationIndexOf(block.timestamp);
        Observation storage observation = poolObservations[pool][index];

        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint256 timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > periodSize) {
            (observation.ratioCumulative, observation.timestamp) = IPool(pool).currentCumulativeRatio();
            emit ObservationRecorded(pool, index, observation);
            updated = true;
        }
    }

    // @inheritdoc IPoolOracle
    function updatePools(IPool[] calldata pools) public override {
        uint length = pools.length;
        for(uint i = 0; i < length;i ++) {
            updatePool(pools[i]);
        }
    }

    /// @inheritdoc IPoolOracle
    function peek(IPool pool) public view override returns (uint256 twar) {
        Observation memory oldestObservation = getOldestObservationInWindow(pool);

        uint256 timeElapsed = block.timestamp - oldestObservation.timestamp;

        // This check is to safeguard the edge case where the pool was initialised just now (or very, very recently)
        // and hence the TWAR can't be trusted as it would be easy to manipulate it.
        // This can happen cause even if we always try to use a value that's `windowSize` old, if said value is stale or invalid
        // we'll loop and try newer ones until we find a valid one (or we blow).
        if (timeElapsed < minTimeElapsed) {
            revert InsufficientElapsedTime(pool, timeElapsed);
        }

        (uint256 currentCumulativeRatio_, ) = IPool(pool).currentCumulativeRatio();
        // cumulative ratio is in (ratio * seconds) units so for the average we simply get it after division by time elapsed
        // cumulative ratio has 27 decimals precision (RAY), the below equation returns a number on 18 decimals precision
        twar = ((currentCumulativeRatio_ - oldestObservation.ratioCumulative) * WAD) / (timeElapsed * RAY);
    }

    /// @inheritdoc IPoolOracle
    function get(IPool pool) public override returns (uint256 twar) {
        updatePool(pool);
        return peek(pool);
    }

    /// @inheritdoc IPoolOracle
    function getSellFYTokenPreview(IPool pool, uint256 fyTokenIn)
        external
        override
        returns (uint256 baseOut, uint256 updateTime)
    {
        (baseOut, updateTime) = _getAmountOverPrice(pool, fyTokenIn, pool.g2());
    }

    /// @inheritdoc IPoolOracle
    function getSellBasePreview(IPool pool, uint256 baseIn)
        external
        override
        returns (uint256 fyTokenOut, uint256 updateTime)
    {
        (fyTokenOut, updateTime) = _getAmountTimesPrice(pool, baseIn, pool.g1());
    }

    /// @inheritdoc IPoolOracle
    function getBuyFYTokenPreview(IPool pool, uint256 fyTokenOut)
        external
        override
        returns (uint256 baseIn, uint256 updateTime)
    {
        (baseIn, updateTime) = _getAmountOverPrice(pool, fyTokenOut, pool.g1());
    }

    /// @inheritdoc IPoolOracle
    function getBuyBasePreview(IPool pool, uint256 baseOut)
        external
        override
        returns (uint256 fyTokenIn, uint256 updateTime)
    {
        (fyTokenIn, updateTime) = _getAmountTimesPrice(pool, baseOut, pool.g2());
    }

    /// @inheritdoc IPoolOracle
    function peekSellFYTokenPreview(IPool pool, uint256 fyTokenIn)
        external
        view
        override
        returns (uint256 baseOut, uint256 updateTime)
    {
        (baseOut, updateTime) = _peekAmountOverPrice(pool, fyTokenIn, pool.g2());
    }

    /// @inheritdoc IPoolOracle
    function peekSellBasePreview(IPool pool, uint256 baseIn)
        external
        view
        override
        returns (uint256 fyTokenOut, uint256 updateTime)
    {
        (fyTokenOut, updateTime) = _peekAmountTimesPrice(pool, baseIn, pool.g1());
    }

    /// @inheritdoc IPoolOracle
    function peekBuyFYTokenPreview(IPool pool, uint256 fyTokenOut)
        external
        view
        override
        returns (uint256 baseIn, uint256 updateTime)
    {
        (baseIn, updateTime) = _peekAmountOverPrice(pool, fyTokenOut, pool.g1());
    }

    /// @inheritdoc IPoolOracle
    function peekBuyBasePreview(IPool pool, uint256 baseOut)
        external
        view
        override
        returns (uint256 fyTokenIn, uint256 updateTime)
    {
        (fyTokenIn, updateTime) = _peekAmountTimesPrice(pool, baseOut, pool.g2());
    }

    function _peekAmountOverPrice(
        IPool pool,
        uint256 amount,
        int128 g
    ) internal view returns (uint256 result, uint256 updateTime) {
        updateTime = block.timestamp;
        uint256 maturity = pool.maturity();
        if (updateTime >= maturity) {
            result = amount;
        } else {
            int128 price = _price(pool, peek(pool), g, maturity, updateTime);
            result = amount.divu(WAD).div(price).mulu(WAD); // result = amount / price
        }
    }

    function _peekAmountTimesPrice(
        IPool pool,
        uint256 amount,
        int128 g
    ) internal view returns (uint256 result, uint256 updateTime) {
        updateTime = block.timestamp;
        uint256 maturity = pool.maturity();
        if (updateTime >= maturity) {
            result = amount;
        } else {
            int128 price = _price(pool, peek(pool), g, maturity, updateTime);
            result = price.mulu(amount); // result = amount * price
        }
    }

    function _getAmountOverPrice(
        IPool pool,
        uint256 amount,
        int128 g
    ) internal returns (uint256 result, uint256 updateTime) {
        updateTime = block.timestamp;
        uint256 maturity = pool.maturity();
        if (updateTime >= maturity) {
            result = amount;
        } else {
            int128 price = _price(pool, get(pool), g, maturity, updateTime);
            result = amount.divu(WAD).div(price).mulu(WAD); // result = amount / price
        }
    }

    function _getAmountTimesPrice(
        IPool pool,
        uint256 amount,
        int128 g
    ) internal returns (uint256 result, uint256 updateTime) {
        updateTime = block.timestamp;
        uint256 maturity = pool.maturity();
        if (updateTime >= maturity) {
            result = amount;
        } else {
            int128 price = _price(pool, get(pool), g, maturity, updateTime);
            result = price.mulu(amount); // result = amount * price
        }
    }

    function _price(
        IPool pool,
        uint256 twar,
        int128 g,
        uint256 maturity,
        uint256 updateTime
    ) internal view returns (int128 price) {
        /*
            https://hackmd.io/VlQkYJ6cTzWIaIyxuR1g2w
            https://www.desmos.com/calculator/39jpmawgpu
            
            price = (c/μ * twar)^t
            price = (c/μ * twar)^(ts*g*ttm)
        */

        // ttm
        int128 timeTillMaturity = (maturity - updateTime).fromUInt();

        // t = ts * g * ttm
        int128 t = pool.ts().mul(g).mul(timeTillMaturity);

        // make twar a binary 64.64 fraction
        int128 twar64 = twar.divu(WAD);

        // price = (c/μ * twar)^t
        price = pool.getC().div(pool.mu()).mul(twar64).pow(t);
    }
}
