// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import '@yield-protocol/utils-v2/contracts/access/AccessControl.sol';
import '@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol';
import '@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol';
import '@yield-protocol/vault-interfaces/src/IOracle.sol';
import '../../constants/Constants.sol';
import './AggregatorV3Interface.sol';
import './FlagsInterface.sol';

/**
 * @title ChainlinkUSDMultiOracle
 * @notice Chainlink only uses USD or ETH as a quote in the aggregators, and we will use only USD
 */
contract ChainlinkUSDMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed baseId, IERC20Metadata base, address indexed source);

    struct Source {
        address source;
        uint8 baseDecimals;
    }

    mapping(bytes6 => Source) public sources;

    /// @dev Set or reset an oracle source and its inverse
    function setSource(
        bytes6 baseId,
        IERC20Metadata base,
        address source
    ) external auth {
        require(AggregatorV3Interface(source).decimals() == 8, 'Non-8-decimals USD source');

        sources[baseId] = Source({source: source, baseDecimals: base.decimals()});
        emit SourceSet(baseId, base, source);
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
        uint80 roundId;
        uint80 answeredInRound;
        Source memory source = sources[baseId];
        require(source.source != address(0), 'Source not found');
        (roundId, price, , updateTime, answeredInRound) = AggregatorV3Interface(source.source).latestRoundData();
        require(price > 0, 'Chainlink price <= 0');
        require(updateTime != 0, 'Incomplete round');
        require(answeredInRound >= roundId, 'Stale price');

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
