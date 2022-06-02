// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/vault-interfaces/src/IOracle.sol";

/**
 * @title CompositeMultiOracle
 */
contract CompositeMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, IOracle indexed source);
    event PathSet(bytes6 indexed baseId, bytes6 indexed quoteId, bytes6[] indexed path);

    mapping(bytes6 => mapping(bytes6 => IOracle)) public sources;
    mapping(bytes6 => mapping(bytes6 => bytes6[])) public paths;

    /// @notice Set or reset a Yearn Vault Token oracle source and its inverse
    /// @param  baseId id used for underlying base token
    /// @param  quoteId id used for underlying quote token
    /// @param  source Oracle contract for source
    function setSource(
        bytes6 baseId,
        bytes6 quoteId,
        IOracle source
    ) external auth {
        sources[baseId][quoteId] = source;
        emit SourceSet(baseId, quoteId, source);

        if (baseId != quoteId) {
            sources[quoteId][baseId] = source;
            emit SourceSet(quoteId, baseId, source);
        }
    }

    /// @notice Set or reset an price path and its reverse path
    /// @param base Id of base token
    /// @param quote Id of quote token
    /// @param path Path from base to quote
    function setPath(
        bytes6 base,
        bytes6 quote,
        bytes6[] calldata path
    ) external auth {
        uint256 pathLength = path.length;
        bytes6[] memory reverse = new bytes6[](pathLength);
        bytes6 base_ = base;
        unchecked {
            for (uint256 p; p < pathLength; ++p) {
                require(sources[base_][path[p]] != IOracle(address(0)), "Source not found");
                base_ = path[p];
                reverse[pathLength - (p + 1)] = base_;
            }
        }
        paths[base][quote] = path;
        paths[quote][base] = reverse;
        emit PathSet(base, quote, path);
        emit PathSet(quote, base, path);
    }

    /// @notice Convert amountBase base into quote at the latest oracle price, through a path is exists.
    /// @param base Id of base token
    /// @param quote Id of quote token
    /// @param amountBase Amount of base to convert to quote
    /// @return amountQuote Amount of quote token converted from base
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amountBase
    ) external view virtual override returns (uint256 amountQuote, uint256 updateTime) {
        updateTime = type(uint256).max;
        amountQuote = amountBase;
        bytes6 base_ = base.b6();
        bytes6 quote_ = quote.b6();
        bytes6[] memory path = paths[base_][quote_];
        uint256 pathLength = path.length;
        unchecked {
            for (uint256 p; p < pathLength; ++p) {
                (amountQuote, updateTime) = _peek(base_, path[p], amountQuote, updateTime);
                base_ = path[p];
            }
        }
        (amountQuote, updateTime) = _peek(base_, quote_, amountQuote, updateTime);
        require(updateTime <= block.timestamp, "Invalid updateTime");
    }

    /// @notice Convert amountBase base into quote at the latest oracle price, through a path is exists.
    /// @dev This function is transactional
    /// @param base Id of base token
    /// @param quote Id of quote token
    /// @param amountBase Amount of base to convert to quote
    /// @return amountQuote Amount of quote token converted from base
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 amountBase
    ) external virtual override returns (uint256 amountQuote, uint256 updateTime) {
        updateTime = type(uint256).max;
        amountQuote = amountBase;
        bytes6 base_ = base.b6();
        bytes6 quote_ = quote.b6();
        bytes6[] memory path = paths[base_][quote_];
        uint256 pathLength = path.length;
        unchecked {
            for (uint256 p; p < pathLength; ++p) {
                (amountQuote, updateTime) = _get(base_, path[p], amountQuote, updateTime);
                base_ = path[p];
            }
        }
        (amountQuote, updateTime) = _get(base_, quote_, amountQuote, updateTime);
        require(updateTime <= block.timestamp, "Invalid updateTime");
    }

    /// @notice Convert amountBase base into quote at the latest oracle price, through a path is exists.
    /// @param base Id of base token
    /// @param quote Id of quote token
    /// @param amountBase Amount of base to convert to quote
    /// @param updateTimeIn Lowest updateTime value obtained received seen until now
    /// @return amountQuote Amount of quote token converted from base
    /// @return updateTimeOut Lower of current price's updateTime or updateTimeIn
    function _peek(
        bytes6 base,
        bytes6 quote,
        uint256 amountBase,
        uint256 updateTimeIn
    ) private view returns (uint256 amountQuote, uint256 updateTimeOut) {
        IOracle source = sources[base][quote];
        require(address(source) != address(0), "Source not found");
        (amountQuote, updateTimeOut) = source.peek(base, quote, amountBase);
        updateTimeOut = (updateTimeOut < updateTimeIn) ? updateTimeOut : updateTimeIn; // Take the oldest update time
    }

    /// @notice Convert amountBase base into quote at the latest oracle price, through a path is exists.
    /// @param base Id of base token
    /// @param quote Id of quote token
    /// @param amountBase Amount of base to convert to quote
    /// @param updateTimeIn Lowest updateTime value obtained received seen until now
    /// @return amountQuote Amount of quote token converted from base
    /// @return updateTimeOut Lower of current price's updateTime or updateTimeIn
    function _get(
        bytes6 base,
        bytes6 quote,
        uint256 amountBase,
        uint256 updateTimeIn
    ) private returns (uint256 amountQuote, uint256 updateTimeOut) {
        IOracle source = sources[base][quote];
        require(address(source) != address(0), "Source not found");
        (amountQuote, updateTimeOut) = source.get(base, quote, amountBase);
        updateTimeOut = (updateTimeOut < updateTimeIn) ? updateTimeOut : updateTimeIn; // Take the oldest update time
    }
}
