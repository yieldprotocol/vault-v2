// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "../interfaces/IOracle.sol";
import "../variable/interfaces/IVRCauldron.sol";
import "../interfaces/ILadle.sol";
import "../constants/Constants.sol";

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
        // @dev ilks
        bytes6[] ilks;
    }

    /* State Variables
     ******************************************************************************************************************/

    mapping(bytes6 => mapping(bytes6 => InterestRateParameter)) public sources;

    IVRCauldron public cauldron;
    ILadle public ladle;

    /* Events
     ******************************************************************************************************************/
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

    constructor(IVRCauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
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
        bytes6[] memory ilks
    ) external auth {
        InterestRateParameter memory source = sources[baseId][kindId];
        require(source.accumulated == 0, "Source is already set");
        IJoin join = ladle.joins(baseId);

        sources[baseId][kindId] = InterestRateParameter({
            optimalUsageRate: optimalUsageRate,
            accumulated: accumulated,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: baseVariableBorrowRate,
            slope1: slope1,
            slope2: slope2,
            join: join,
            ilks: ilks
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

    function updateParameters(
        bytes6 baseId,
        bytes6 kindId,
        uint256 optimalUsageRate,
        uint256 baseVariableBorrowRate,
        uint256 slope1,
        uint256 slope2
    ) external auth {
        InterestRateParameter memory source = sources[baseId][kindId];
        require(source.accumulated != 0, "Source not found");

        require(
            source.lastUpdated == block.timestamp,
            "stale InterestRateParameter"
        );
        IJoin join = ladle.joins(baseId);
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

        updateTime = source.lastUpdated;
    }

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
            // Calculate the total debt
            uint128 totalDebt;
            DataTypes.Debt memory debt_;
            debt_ = cauldron.debt(base.b6(), base.b6());
            totalDebt = totalDebt + debt_.sum;

            for (uint256 i = 0; i < rateParameters.ilks.length; i++) {
                if (cauldron.ilks(base.b6(), rateParameters.ilks[i])) {
                    debt_ = cauldron.debt(base.b6(), rateParameters.ilks[i]);
                    totalDebt = totalDebt + debt_.sum;
                }
            }

            // Calculate utilization rate
            // Total debt / Total Liquidity
            uint256 utilizationRate = uint256(totalDebt).wdiv(
                rateParameters.join.storedBalance()
            );

            uint256 interestRate;
            if (utilizationRate <= rateParameters.optimalUsageRate) {
                interestRate =
                    rateParameters.baseVariableBorrowRate +
                    utilizationRate.wmul(rateParameters.slope1).wdiv(
                        rateParameters.optimalUsageRate
                    );
            } else {
                interestRate =
                    rateParameters.baseVariableBorrowRate +
                    rateParameters.slope1 +
                    (utilizationRate - rateParameters.optimalUsageRate)
                        .wmul(rateParameters.slope2)
                        .wdiv(1e18 - rateParameters.optimalUsageRate);
            }
            // Calculate per second rate
            interestRate = interestRate / 365 days;
            rateParameters.accumulated *= (1e18 + interestRate).wpow(
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
