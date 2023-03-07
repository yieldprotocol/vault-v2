// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "../interfaces/IOracle.sol";

/**
 * @title IdentityOracle
 * @notice This oracle is used to convert between two tokens 1:1 with the different decimals.
 */
contract IdentityOracle is IOracle, AccessControl {
    using Cast for bytes32;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address base,
        address quote
    );

    struct Source {
        uint8 baseDecimals;
        uint8 quoteDecimals;
        bool set;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /// @dev Set or reset an oracle source and its inverse
    function setSource(
        bytes6 baseId,
        bytes6 quoteId,
        IERC20Metadata base,
        IERC20Metadata quote
    ) external auth {
        require(baseId != quoteId, "Wrong input");
        sources[baseId][quoteId] = Source({
            baseDecimals: base.decimals(),
            quoteDecimals: quote.decimals(),
            set: true
        });
        emit SourceSet(baseId, quoteId, address(base), address(quote));

        sources[quoteId][baseId] = Source({
            baseDecimals: quote.decimals(), // We are reversing the base and the quote
            quoteDecimals: base.decimals(),
            set: true
        });
        emit SourceSet(quoteId, baseId, address(quote), address(base));
    }

    /// @dev Convert amountBase base into quote at 1:1.
    function peek(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    )
        external
        view
        virtual
        override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        (amountQuote, updateTime) = _peek(
            baseId.b6(),
            quoteId.b6(),
            amountBase
        );
    }

    /// @dev Convert amountBase base into quote at 1:1, updating state if necessary. Same as `peek` for this oracle.
    function get(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    )
        external
        virtual
        override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        (amountQuote, updateTime) = _peek(
            baseId.b6(),
            quoteId.b6(),
            amountBase
        );
    }

    /// @dev Convert amountBase base into quote at 1:1 taking decimals into account.
    function _peek(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amountBase
    ) private view returns (uint256 amountQuote, uint256 updateTime) {
        Source memory source = sources[baseId][quoteId];
        require(source.set == true, "Source not found");
        amountQuote =
            (amountBase * (10**source.quoteDecimals)) /
            (10**source.baseDecimals);
        updateTime = block.timestamp;
    }
}
