// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import {IOracle} from "@yield-protocol/vault-interfaces/src/IOracle.sol";
import {CastBytes32Bytes6} from "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import {IEToken} from "./IEToken.sol";
import {AccessControl} from "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

contract ETokenMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    struct Source {
        address source;
        bool inverse;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, address indexed source, bool inverse);

    function setSource(
        bytes6 underlyingId,
        bytes6 eTokenId,
        IEToken eToken
    ) external auth {
        _setSource(eTokenId, underlyingId, eToken, false);
        _setSource(underlyingId, eTokenId, eToken, true);
    }

    function _setSource(
        bytes6 baseId,
        bytes6 quoteId,
        IEToken source,
        bool inverse
    ) internal {
        sources[baseId][quoteId] = Source({source: address(source), inverse: inverse});

        emit SourceSet(baseId, quoteId, address(source), inverse);
    }

    function peek(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view returns (uint256 value, uint256 updateTime) {
        return _peek(baseId.b6(), quoteId.b6(), amountBase);
    }

    function get(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view returns (uint256 value, uint256 updateTime) {
        return _peek(baseId.b6(), quoteId.b6(), amountBase);
    }

    function _peek(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amountBase
    ) internal view returns (uint256 amountQuote, uint256 updateTime) {
        updateTime = block.timestamp;

        if (baseId == quoteId) return (amountBase, updateTime);

        Source memory source = sources[baseId][quoteId];
        require(source.source != address(0), "Source not found");

        if (source.inverse == false) {
            amountQuote = IEToken(source.source).convertBalanceToUnderlying(amountBase);
        } else {
            amountQuote = IEToken(source.source).convertUnderlyingToBalance(amountBase);
        }
    }
}
