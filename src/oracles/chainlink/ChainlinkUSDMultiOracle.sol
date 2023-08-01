// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "../../interfaces/IOracle.sol";
import "./OffchainAggregatorInterface.sol";
import "../../constants/Constants.sol";
import "./AggregatorV3Interface.sol";
import "./FlagsInterface.sol";

/**
 * @title ChainlinkUSDMultiOracle
 * @notice Chainlink only uses USD or ETH as a quote in the aggregators, and we will use only USD
 */
contract ChainlinkUSDMultiOracle is IOracle, AccessControl, Constants {
    using Cast for *;

    event SourceSet(bytes6 indexed baseId, IERC20Metadata base, address indexed source);
    event LimitsSet(bytes6 indexed baseId, uint96 minAnswer, uint128 maxAnswer, uint32 heartbeat);

    struct Source {
        address source;
        uint8 baseDecimals;
    }

    struct Limits {
        uint32 heartbeat;  // Max time in seconds between updates
        uint96 minAnswer;  // Min answer below which the aggregator stops reporting
        uint128 maxAnswer; // Max answer above which the aggregator stops reporting
    }

    mapping(bytes6 => Source) public sources;
    mapping(bytes6 => Limits) public limits;

    /// @dev Set or reset an oracle source and its inverse
    function setSource(
        bytes6 baseId,
        IERC20Metadata base,
        address source,
        uint32 heartbeat
    ) external auth {
        require(AggregatorV3Interface(source).decimals() == 8, "Non-8-decimals USD source");

        sources[baseId] = Source({source: source, baseDecimals: base.decimals()});
        emit SourceSet(baseId, base, source);

        (uint96 minAnswer, uint128 maxAnswer) = _calculateLimits(source, heartbeat);
        _setLimits(baseId, minAnswer, maxAnswer, heartbeat);

    }

    /// @dev Set limits manually
    function setLimits(bytes6 baseId, uint96 minAnswer, uint128 maxAnswer, uint32 heartbeat)
        external auth
    {
        _setLimits(baseId, minAnswer, maxAnswer, heartbeat);
    }

    function _calculateLimits(address source, uint32 heartbeat) internal view returns(uint96 minAnswer, uint128 maxAnswer) {
        OffchainAggregatorInterface aggregator = OffchainAggregatorInterface(AggregatorV3Interface(source).aggregator());

        (, int256 price,, uint256 updateTime,) = AggregatorV3Interface(source).latestRoundData();
        require(price > 0, "Chainlink price <= 0");

        // Make sure blocktime - updateTime is below heartbeat
        require(block.timestamp - updateTime <= heartbeat, "Heartbeat exceeded");

        // Deal with the limits being to large to be casted into uint96 and uint128 respectively
        minAnswer = int256(aggregator.minAnswer()).u256().u96(); // If the minAnswer is above 2^96, we are better off reverting
        uint256 maxAnswer_ = int256(aggregator.maxAnswer()).u256();
        maxAnswer = maxAnswer_ > type(uint128).max ? type(uint128).max : maxAnswer_.u128(); // If the maxAnswer is above 2^128, we are better off truncating

        // Increase minAnswer by a 10% of the distance to the current price
        minAnswer = minAnswer + ((price.u256() - uint256(minAnswer)) / 10).u96();
        // Decrease maxAnswer by a 10% of the distance to the current price
        maxAnswer = maxAnswer - ((uint256(maxAnswer) - price.u256()) / 10).u128();
    }

    /// @dev Set or reset the `minAnswer` and `maxAnswer`. The original values are taken from the aggregator, and the distance between them is reduced by a 20%.
    function _setLimits(bytes6 baseId,uint96 minAnswer, uint128 maxAnswer, uint32 heartbeat)
        internal
    {
        limits[baseId] = Limits({
            heartbeat: heartbeat,
            minAnswer: minAnswer, 
            maxAnswer: maxAnswer
        });
        emit LimitsSet(baseId, minAnswer, maxAnswer, heartbeat);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price.
    function peek(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view virtual override returns (uint256 amountQuote, uint256 updateTime) {
        if (baseId == quoteId) return (amountBase, block.timestamp);

        (amountQuote, updateTime) = _peekThroughUSD(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, updating state if necessary. Same as `peek` for this oracle.
    function get(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external virtual override returns (uint256 amountQuote, uint256 updateTime) {
        if (baseId == quoteId) return (amountBase, block.timestamp);

        (amountQuote, updateTime) = _peekThroughUSD(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev returns price for `baseId` in USD and base (not USD!) decimals
    function _getPriceInUSD(bytes6 baseId)
        private
        view
        returns (
            uint256 uintPrice,
            uint256 updateTime,
            uint8 baseDecimals
        )
    {
        int256 price;
        Source memory source = sources[baseId];
        require(source.source != address(0), "Source not found");
        (, price,, updateTime,) = AggregatorV3Interface(source.source).latestRoundData();
        require(price > 0, "Chainlink price <= 0");

        Limits memory limit = limits[baseId];
        // Make sure blocktime - updateTime is below heartbeat
        require(block.timestamp - updateTime <= limit.heartbeat, "Heartbeat exceeded");
        // Check that answer is above `minAnswer`
        require(uint(price) >= limit.minAnswer, "Below minAnswer");
        // Check that answer is below `maxAnswer`
        require(uint(price) <= limit.maxAnswer, "Above maxAnswer");

        uintPrice = uint256(price);
        baseDecimals = source.baseDecimals;
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, using USD as an intermediate step.
    function _peekThroughUSD(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amountBase
    ) internal view returns (uint256 amountQuote, uint256 updateTime) {
        (uint256 basePrice, uint256 updateTime1, uint8 baseDecimals) = _getPriceInUSD(baseId);
        (uint256 quotePrice, uint256 updateTime2, uint8 quoteDecimals) = _getPriceInUSD(quoteId);

        // decimals: baseDecimals * udcDecimals / usdDecimals
        amountQuote = (amountBase * basePrice) / quotePrice;

        // now need to convert baseDecimals to quoteDecimals
        if (baseDecimals <= quoteDecimals) {
            amountQuote *= (10**(quoteDecimals - baseDecimals));
        } else {
            amountQuote /= (10**(baseDecimals - quoteDecimals));
        }

        updateTime = (updateTime1 < updateTime2) ? updateTime1 : updateTime2;
    }
}
