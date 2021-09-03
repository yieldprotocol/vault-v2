// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";


/**
 * @title CompositeMultiOracle
 */
contract CompositeMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, IOracle indexed source);
    event PathSet(bytes6 indexed baseId, bytes6 indexed quoteId, bytes6[] indexed path);

    mapping(bytes6 => mapping(bytes6 => IOracle)) public sources;
    mapping(bytes6 => mapping(bytes6 => bytes6[])) public paths;

    /// @dev Set or reset an oracle source
    function setSource(bytes6 baseId, bytes6 quoteId, IOracle source)
        external auth
    {
        sources[baseId][quoteId] = source;
        emit SourceSet(baseId, quoteId, source);

        if (baseId != quoteId) {
            sources[quoteId][baseId] = source;
            emit SourceSet(quoteId, baseId, source);
        }
    }

    /// @dev Set or reset an price path
    function setPath(bytes6 base, bytes6 quote, bytes6[] memory path)
        external auth
    {
        bytes6[] memory reverse = new bytes6[](path.length);
        bytes6 base_ = base;
        for (uint256 p = 0; p < path.length; p++) {
            require (sources[base_][path[p]] != IOracle(address(0)), "Source not found");
            base_ = path[p];
            reverse[path.length - (p + 1)] = base_;
        }
        paths[base][quote] = path;
        paths[quote][base] = reverse;
        emit PathSet(base, quote, path);
        emit PathSet(quote, base, path);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, through a path is exists.
    function peek(bytes32 base, bytes32 quote, uint256 amountBase)
        external view virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        amountQuote = amountBase;
        bytes6 base_ = base.b6();
        bytes6 quote_ = quote.b6();
        bytes6[] memory path = paths[base_][quote_];
        for (uint256 p = 0; p < path.length; p++) {
            (amountQuote, updateTime) = _peek(base_, path[p], amountQuote, updateTime);
            base_ = path[p];
        }
        (amountQuote, updateTime) = _peek(base_, quote_, amountQuote, updateTime);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, through a path is exists, updating state if necessary.
    function get(bytes32 base, bytes32 quote, uint256 amountBase)
        external virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        amountQuote = amountBase;
        bytes6 base_ = base.b6();
        bytes6 quote_ = quote.b6();
        bytes6[] memory path = paths[base_][quote_];
        for (uint256 p = 0; p < path.length; p++) {
            (amountQuote, updateTime) = _get(base_, path[p], amountQuote, updateTime);
            base_ = path[p];
        }
        (amountQuote, updateTime) = _get(base_, quote_, amountQuote, updateTime);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, using only direct sources.
    function _peek(bytes6 base, bytes6 quote, uint256 amountBase, uint256 updateTimeIn)
        private view
        returns (uint amountQuote, uint updateTimeOut)
    {
        IOracle source = sources[base][quote];
        require (address(source) != address(0), "Source not found");
        (amountQuote, updateTimeOut) = source.peek(base, quote, amountBase);
        updateTimeOut = (updateTimeOut < updateTimeIn) ? updateTimeOut : updateTimeIn;                 // Take the oldest update time
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, using only direct sources, updating state if necessary.
    function _get(bytes6 base, bytes6 quote, uint256 amountBase, uint256 updateTimeIn)
        private
        returns (uint amountQuote, uint updateTimeOut)
    {
        IOracle source = sources[base][quote];
        require (address(source) != address(0), "Source not found");
        (amountQuote, updateTimeOut) = source.get(base, quote, amountBase);
        updateTimeOut = (updateTimeOut < updateTimeIn) ? updateTimeOut : updateTimeIn;                 // Take the oldest update time
    }
}