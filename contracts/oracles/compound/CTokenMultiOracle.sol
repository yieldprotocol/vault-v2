// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "../../constants/Constants.sol";
import "./CTokenInterface.sol";


contract CTokenMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, CTokenInterface indexed cToken);

    struct Source {
        CTokenInterface source;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        bool inverse;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /// @dev Set or reset an oracle source and its inverse
    function setSource(bytes6 cTokenId, bytes6 underlyingId, CTokenInterface cToken)
        external auth
    {
        IERC20Metadata underlying = IERC20Metadata(cToken.underlying());
        uint8 underlyingDecimals = underlying.decimals();
        uint8 cTokenDecimals = underlyingDecimals + 10; // https://compound.finance/docs/ctokens#exchange-rate
        sources[cTokenId][underlyingId] = Source({
            source: cToken,
            baseDecimals: cTokenDecimals,
            quoteDecimals: underlyingDecimals,
            inverse: false
        });
        emit SourceSet(cTokenId, underlyingId, cToken);

        sources[underlyingId][cTokenId] = Source({
            source: cToken,
            baseDecimals: underlyingDecimals, // We are reversing the base and the quote
            quoteDecimals: cTokenDecimals,
            inverse: true
        });
        emit SourceSet(underlyingId, cTokenId, cToken);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function peek(bytes32 base, bytes32 quote, uint256 amountBase)
        external view virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        Source memory source = sources[base.b6()][quote.b6()];
        require (source.source != CTokenInterface(address(0)), "Source not found");

        uint256 price = source.source.exchangeRateStored();
        require(price > 0, "Compound price is zero");

        if (source.inverse == true) {
            // ETH/USDC: 1 ETH (*10^18) * (1^6)/(286253688799857 ETH per USDC) = 3493404763 USDC wei
            amountQuote = amountBase * (10 ** source.quoteDecimals) / uint(price);
        } else {
            // USDC/ETH: 3000 USDC (*10^6) * 286253688799857 ETH per USDC / 10^6 = 858761066399571000 ETH wei
            amountQuote = uint(price) * amountBase / (10 ** source.baseDecimals);
        }
        updateTime = block.timestamp; // TODO: We should get the timestamp
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Updates the price before fetching it if possible.
     */
    function get(bytes32 base, bytes32 quote, uint256 amountBase)
        external virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        Source memory source = sources[base.b6()][quote.b6()];
        require (source.source != CTokenInterface(address(0)), "Source not found");

        uint256 price = source.source.exchangeRateCurrent();
        require(price > 0, "Compound price is zero");
        
        if (source.inverse == true) {
            // USDC/cUSDC: 1 USDC (*10^6) * (1^16)/(x USDC per cUSDC) = y cUSDC wei
            amountQuote = amountBase * (10 ** source.quoteDecimals) / uint(price);
        } else {
            // cUSDC/USDC: 3000 cUSDC (*10^18) * x USDC per cUSDC / 10^16 = y USDC wei
            amountQuote = amountBase * uint(price) / (10 ** source.baseDecimals);
        }  
        updateTime = block.timestamp; // TODO: We should get the timestamp
    }
}