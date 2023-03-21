// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ICauldron.sol";
import "../constants/Constants.sol";
import "forge-std/src/console2.sol";

/**
A collection of independent Accumulator Oracles

Each Accumulator is simple: it starts when `setSource` is called, 
and each `get` call returns perSecondRate ^ (time in seconds since oracle creation)
 */
contract VariableInterestRateOracle is IOracle, AccessControl, Constants {
    using Cast for bytes32;
    using Math for uint256;

    struct InterestRateParameter {
        /// @dev rate accumulated so far - check `get` for details
        uint256 accumulated;
        /// @dev time when `accumulated` was last updated
        uint256 lastUpdated;
        // @dev optimalUsageRate
        uint256 optimalUsageRate;
        // @dev baseVariableBorrowRate
        uint256 baseVariableBorrowRate;
        // @dev slope1
        uint256 slope1;
        // @dev slope2
        uint256 slope2;
        // @dev join
        IJoin join;
    }

    mapping(bytes6 => mapping(bytes6 => InterestRateParameter)) public sources;
    ICauldron public cauldron;
    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed kind,
        uint256 optimalUsageRate,
        uint256 baseVariableBorrowRate,
        uint256 slope1,
        uint256 slope2,
        IJoin join
    );
    event PerSecondRateUpdated(
        bytes6 indexed baseId,
        bytes6 indexed kind,
        uint256 optimalUsageRate,
        uint256 baseVariableBorrowRate,
        uint256 slope1,
        uint256 slope2,
        IJoin join
    );

    constructor(ICauldron cauldron_) {
        cauldron = cauldron_;
    }

    /** 
    @notice Set a source
     */
    function setSource(
        bytes6 baseId,
        bytes6 kindId,
        uint256 optimalUsageRate,
        uint256 accumulated,
        uint256 baseVariableBorrowRate,
        uint256 slope1,
        uint256 slope2,
        IJoin join
    ) external auth {
        InterestRateParameter memory source = sources[baseId][kindId];
        require(source.accumulated == 0, "Source is already set");

        sources[baseId][kindId] = InterestRateParameter({
            optimalUsageRate: optimalUsageRate,
            accumulated: accumulated,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: baseVariableBorrowRate,
            slope1: slope1,
            slope2: slope2,
            join: join
        });
        emit SourceSet(
            baseId,
            kindId,
            optimalUsageRate,
            baseVariableBorrowRate,
            slope1,
            slope2,
            join
        );
    }

    /**
    @notice Updates accumulation rate
    
    The accumulation rate can only be updated on an up-to-date oracle: get() was called in the
    same block. See get() for more details
     */
    function updateParameters(
        bytes6 baseId,
        bytes6 kindId,
        uint256 optimalUsageRate,
        uint256 baseVariableBorrowRate,
        uint256 slope1,
        uint256 slope2,
        IJoin join
    ) external auth {
        InterestRateParameter memory source = sources[baseId][kindId];
        require(source.accumulated != 0, "Source not found");

        require(
            source.lastUpdated == block.timestamp,
            "stale InterestRateParameter"
        );
        sources[baseId][kindId].optimalUsageRate = optimalUsageRate;
        sources[baseId][kindId].baseVariableBorrowRate = baseVariableBorrowRate;
        sources[baseId][kindId].slope1 = slope1;
        sources[baseId][kindId].slope2 = slope2;
        sources[baseId][kindId].join = join;

        emit PerSecondRateUpdated(
            baseId,
            kindId,
            optimalUsageRate,
            baseVariableBorrowRate,
            slope1,
            slope2,
            join
        );
    }

    /**
     * @notice Retrieve the latest stored accumulated rate.
     */
    function peek(
        bytes32 base,
        bytes32 kind,
        uint256
    )
        external
        view
        virtual
        override
        returns (uint256 accumulated, uint256 updateTime)
    {
        InterestRateParameter memory source = sources[base.b6()][kind.b6()];
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
    )
        external
        virtual
        override
        returns (uint256 accumulated, uint256 updateTime)
    {
        InterestRateParameter memory rateParameters = sources[base.b6()][
            kind.b6()
        ];
        require(rateParameters.accumulated != 0, "Source not found");

        uint256 secondsSinceLastUpdate = (block.timestamp -
            rateParameters.lastUpdated);
        if (secondsSinceLastUpdate > 0) {
            //1. Calculate the utilization rate
            DataTypes.Debt memory debt_ = cauldron.debt(base.b6(), base.b6());
            // Total borrows / Total Liquidity
            uint256 utilizationRate = uint256(debt_.sum).wdiv(
                rateParameters.join.storedBalance()
            );

            uint256 borrowRate = 0;

            if (utilizationRate <= rateParameters.optimalUsageRate * 1e12) {
                borrowRate =
                    rateParameters.baseVariableBorrowRate +
                    (utilizationRate.wmul(rateParameters.slope1 * 1e12)).wdiv(
                        rateParameters.optimalUsageRate * 1e12
                    );
            } else {
                borrowRate =
                    rateParameters.baseVariableBorrowRate +
                    rateParameters.slope1 *
                    1e12 +
                    (utilizationRate - rateParameters.optimalUsageRate * 1e12)
                        .wmul(rateParameters.slope2 * 1e12)
                        .wdiv(1e18 - rateParameters.optimalUsageRate * 1e12);
            }
            // Calculate per second rate
            // borrowRate = (borrowRate * 1e12)/(365 days);

            rateParameters.accumulated *= borrowRate.wpow(
                secondsSinceLastUpdate
            );
            rateParameters.accumulated /= 1e18;
            rateParameters.lastUpdated = block.timestamp;

            sources[base.b6()][kind.b6()] = rateParameters;
        }

        accumulated = rateParameters.accumulated;
        require(accumulated > 0, "Accumulated rate is zero");
        updateTime = block.timestamp;
    }
}
