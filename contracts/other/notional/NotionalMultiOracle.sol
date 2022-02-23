// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";


/**
 * @title NotionalMultiOracle
 * @notice We value fCash assets at face value
 */
contract NotionalMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed notionalId, bytes6 indexed underlyingId, address underlying);

    struct Source {
        uint8 baseDecimals;
        uint8 quoteDecimals;
        bool inverse;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /// @dev Set or reset an oracle source and its inverse
    function setSource(bytes6 notionalId, bytes6 underlyingId, IERC20Metadata underlying)
        external auth
    {
        require (notionalId != underlyingId, "Wrong input");
        sources[notionalId][underlyingId] = Source({
            baseDecimals: 18, // I'm assuming here that fCash has 18 decimals
            quoteDecimals: underlying.decimals(), // Ideally we would get the underlying from fCash
            inverse: false
        });
        emit SourceSet(notionalId, underlyingId, address(underlying));

        sources[underlyingId][notionalId] = Source({
            baseDecimals: underlying.decimals(), // We are reversing the base and the quote
            quoteDecimals: 18,
            inverse: true
        });
        emit SourceSet(underlyingId, notionalId, address(underlying));
    }

    /// @dev Convert amountBase base into quote at the latest oracle price.
    function peek(bytes32 baseId, bytes32 quoteId, uint256 amountBase)
        external view virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        (amountQuote, updateTime) = _peek(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, updating state if necessary. Same as `peek` for this oracle.
    function get(bytes32 baseId, bytes32 quoteId, uint256 amountBase)
        external virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        (amountQuote, updateTime) = _peek(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price.
    function _peek(bytes6 baseId, bytes6 quoteId, uint256 amountBase)
        private view
        returns (uint amountQuote, uint updateTime)
    {
        Source memory source = sources[baseId][quoteId];
        require (source.baseDecimals == 18 || source.quoteDecimals == 18, "Source not found"); // A bit meh as a test of existence
        int price = 1e18; // We price fCash at face value
        if (source.inverse == true) {
            // fUSDC/USDC: 1 fUSDC (*10^18) * (1^6)/(10^18 fUSDC per USDC) = 10^6 USDC wei
            amountQuote = amountBase * (10 ** source.baseDecimals) / (10 ** source.quoteDecimals);
        } else {
            // USDC/fUSDC: 1 USDC (*10^6) * 10^18 fUSDC per USDC / 10^6 = 10^18 fUSDC wei
            amountQuote = amountBase * (10 ** source.quoteDecimals) / (10 ** source.baseDecimals);
        }
        updateTime = block.timestamp;
    }
}
