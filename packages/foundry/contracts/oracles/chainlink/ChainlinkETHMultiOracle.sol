// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/vault-interfaces/src/IOracle.sol";
import "../../constants/Constants.sol";
import "./AggregatorV3Interface.sol";


/**
 * @title ChainlinkMultiOracle
 * @notice Chainlink only uses USD or ETH as a quote in the aggregators, and we will use only ETH
 */
contract ChainlinkETHMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed assetId, IERC20Metadata asset, address indexed source);

    struct Source {
        address source;
        uint8 assetDecimals;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /// @dev Set or reset an oracle source and its inverse
    function setSource(bytes6 assetId, IERC20Metadata asset, address source)
        external auth
    {
        require(AggregatorV3Interface(source).decimals() == 18, 'Non-18-decimals ETH source');

        sources[assetId] = Source({source: source, assetDecimals: asset.decimals()});
        emit SourceSet(assetId, asset, source);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price.
    function peek(bytes32 baseId, bytes32 quoteId, uint256 amountBase)
        external view virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        if (baseId == ETH || quoteId == ETH)
            (amountQuote, updateTime) = _peek(baseId.b6(), quoteId.b6(), amountBase);
        else
            (amountQuote, updateTime) = _peekThroughETH(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, updating state if necessary. Same as `peek` for this oracle.
    function get(bytes32 baseId, bytes32 quoteId, uint256 amountBase)
        external virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        if (baseId == ETH || quoteId == ETH)
            (amountQuote, updateTime) = _peek(baseId.b6(), quoteId.b6(), amountBase);
        else
            (amountQuote, updateTime) = _peekThroughETH(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price.
    function _peek(bytes6 baseId, bytes6 quoteId, uint256 amountBase)
        private view
        returns (uint amountQuote, uint updateTime)
    {
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
            amountQuote = amountBase * (10 ** source.quoteDecimals) / uint(price);
        } else {
            // USDC/ETH: 3000 USDC (*10^6) * 286253688799857 ETH per USDC / 10^6 = 858761066399571000 ETH wei
            amountQuote = amountBase * uint(price) / (10 ** source.baseDecimals);
        }  
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, using ETH as an intermediate step.
    function _peekThroughETH(bytes6 baseId, bytes6 quoteId, uint256 amountBase)
        private view
        returns (uint amountQuote, uint updateTime)
    {
        (uint256 ethAmount, uint256 updateTime1) = _peek(baseId, ETH, amountBase);
        (amountQuote, updateTime) = _peek(ETH, quoteId, ethAmount);
        if (updateTime1 < updateTime) updateTime = updateTime1;
    }
}
