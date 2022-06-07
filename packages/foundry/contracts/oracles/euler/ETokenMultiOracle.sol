// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import {IOracle} from "@yield-protocol/vault-interfaces/src/IOracle.sol";
import {CastBytes32Bytes6} from "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import {IEToken} from "./IEToken.sol";
import {AccessControl} from "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";


/// @title ETokenMultiOracle (Euler EToken)
/// @author davidbrai
/// @notice Converts from Euler EToken to underlying and vice-versa, e.g. eDAI <-> DAI
/// @dev peek() and get() are effectively the same in this case, calling the EToken contract for current values
contract ETokenMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    struct Source {
        /// @dev EToken contract address
        address source;

        /// @dev Indicates if EToken should be used for converting EToken to underlying (inverse == false)
        ///     or underlying to EToken (inverse == true)
        bool inverse;
    }

    /******************
     * Storage
     ******************/

    /// @dev baseId => quoteId => Source
    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /******************
     * Events
     ******************/

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, address indexed source, bool inverse);

    /// @notice Set or reset an EToken to be used as an oracle for converting EToken <-> underlying (both directions)
    /// @param underlyingId id used for underlying base token (e.g. DAI)
    /// @param eTokenId id used for Euler EToken (e.g. eDAI)
    /// @param eToken address of an Euler EToken contract to be used as the oracle
    /// @dev This function is accessible only with permissioned access control
    function setSource(
        bytes6 underlyingId,
        bytes6 eTokenId,
        IEToken eToken
    ) external auth {
        _setSource(eTokenId, underlyingId, eToken, false);
        _setSource(underlyingId, eTokenId, eToken, true);
    }

    /// @notice Convert `amountBase` of `baseId` tokens to its value in `quoteId`
    /// @dev This function calculates the current prices, i.e doesn't use cached values
    /// @param baseId id of base token
    /// @param quoteId id of quote, returned amount denominated in this token
    /// @param amountBase amount in base to convert
    /// @return amountQuote converted amountBase into quote tokens
    /// @return updateTime current block timestamp
    function get(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view returns (uint256 amountQuote, uint256 updateTime) {
        return _peek(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @notice Convert `amountBase` of `baseId` tokens to its value in `quoteId`
    /// @dev Identical to the `get` function, provided here as convenience to follow IOracle interface
    function peek(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view returns (uint256 amountQuote, uint256 updateTime) {
        return _peek(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Updates the `sources` storage mapping and emits event
    /// @param baseId id of base token
    /// @param quoteId id of quoted token
    /// @param source address of Euler EToken contract to use for conversion
    /// @param inverse set true to use the EToken contract to convert from underlying to EToken, false otherwise
    function _setSource(
        bytes6 baseId,
        bytes6 quoteId,
        IEToken source,
        bool inverse
    ) internal {
        sources[baseId][quoteId] = Source({source: address(source), inverse: inverse});

        emit SourceSet(baseId, quoteId, address(source), inverse);
    }

    /// @notice Internal function that actually does the conversion of underlying <-> EToken
    /// @dev Uses `EToken.convertBalanceToUnderlying` and `EToken.convertUnderlyingToBalance`
    /// @param baseId id of base token
    /// @param quoteId id of quote, returned amount denominated in this token
    /// @param amountBase amount in base to convert
    /// @return amountQuote converted amountBase into quote tokens
    /// @return updateTime current block timestamp
    function _peek(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amountBase
    ) internal view returns (uint256 amountQuote, uint256 updateTime) {
        updateTime = block.timestamp;

        Source memory source = sources[baseId][quoteId];
        require(source.source != address(0), "Source not found");

        if (source.inverse == false) {
            amountQuote = IEToken(source.source).convertBalanceToUnderlying(amountBase);
        } else {
            amountQuote = IEToken(source.source).convertUnderlyingToBalance(amountBase);
        }
    }
}
