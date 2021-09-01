// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "../../constants/Constants.sol";
import "./AggregatorV3Interface.sol";


/**
 * @title ChainlinkMultiOracle
 * @notice Chainlink only uses USD or ETH as a quote in the aggregators, and we will use only ETH
 */
contract ChainlinkMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;

    uint8 public constant override decimals = 18;   // TODO: Remove from IOracle, it makes no sense

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, address indexed source);

    struct Source {
        address source;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        bool inverse;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /**
     * @notice Set or reset an oracle source and its inverse
     */
    function setSource(bytes6 baseId, IERC20Metadata base, bytes6 quoteId, IERC20Metadata quote, address source) external auth {
        _setSource(baseId, base, quoteId, quote, source);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function peek(bytes32 baseId, bytes32 quoteId, uint256 amount)
        external view virtual override
        returns (uint256 value, uint256 updateTime)
    {
        (value, updateTime) = _peek(baseId.b6(), quoteId.b6(), amount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     */
    function get(bytes32 baseId, bytes32 quoteId, uint256 amount)
        external virtual override
        returns (uint256 value, uint256 updateTime)
    {
        (value, updateTime) = _peek(baseId.b6(), quoteId.b6(), amount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function _peek(bytes6 baseId, bytes6 quoteId, uint256 amount) private view returns (uint value, uint updateTime) {
        int price;
        uint80 roundId;
        uint80 answeredInRound;
        Source memory source = sources[baseId][quoteId];
        require (source.source != address(0), "Source not found");
        (roundId, price,, updateTime, answeredInRound) = AggregatorV3Interface(source.source).latestRoundData();
        require(price > 0, "Chainlink price <= 0");
        require(updateTime != 0, "Incomplete round");
        require(answeredInRound >= roundId, "Stale price");
        if (source.inverse == true) {
            // ETH/USDC: 1 ETH (*10^18) * (1^6)/(286253688799857 ETH per USDC) = 3493404763 USDC wei
            value = amount * (10 ** source.quoteDecimals) / uint(price);
        } else {
            // USDC/ETH: 3000 USDC (*10^6) * 286253688799857 ETH per USDC / 10^6 = 858761066399571000 ETH wei
            value = uint(price) * amount / (10 ** source.baseDecimals);
        }  
    }

    /**
     * @dev Set a new price source
     */
    function _setSource(bytes6 baseId, IERC20Metadata base, bytes6 quoteId, IERC20Metadata quote, address source) internal {
        sources[baseId][quoteId] = Source({
            source: source,
            baseDecimals: base.decimals(),
            quoteDecimals: quote.decimals(),
            inverse: false
        });
        sources[quoteId][baseId] = Source({
            source: source,
            baseDecimals: quote.decimals(), // We are reversing the base and the quote
            quoteDecimals: base.decimals(),
            inverse: true
        });
        emit SourceSet(baseId, quoteId, source);
        emit SourceSet(quoteId, baseId, source);
    }
}
