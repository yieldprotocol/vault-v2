// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "../../interfaces/IOracle.sol";
import "../../interfaces/IStrategy.sol";

/// @title Oracle contract to get price of strategy tokens in terms of base & vice versa
/// @author iamsahu
/// @dev value of 1 LP token = 1 base
contract StrategyOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        IStrategy indexed strategy
    );

    struct Source {
        bool inverse;
        IStrategy strategy;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    function setSource(bytes6 strategyId, IStrategy strategy) external auth {
        bytes6 quoteId = strategy.baseId();
        sources[strategyId][quoteId] = Source({
            strategy: strategy,
            inverse: false
        });
        emit SourceSet(strategyId, quoteId, strategy);

        // Storing the inverse by default as we can assume that quoteId will never be the same as strategyId
        sources[quoteId][strategyId] = Source({
            strategy: strategy,
            inverse: true
        });
        emit SourceSet(quoteId, strategyId, strategy);
    }

    function peek(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amount
    ) external view returns (uint256 value, uint256 updateTime) {
        return _peek(baseId.b6(), quoteId.b6(), amount);
    }

    function _peek(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amount
    ) internal view returns (uint256 value, uint256 updateTime) {
        updateTime = block.timestamp;
        Source memory source = sources[baseId][quoteId];
        require(address(source.strategy) != address(0), "Source not found");
        if (source.inverse == true) {
            value =
                (amount * source.strategy.totalSupply()) /
                source.strategy.cached();
        } else {
            // value of 1 strategy token =  number of LP tokens in strat(cached)
            //                            ---------------------------------------
            //                              totalSupply of strategy tokens
            value =
                (amount * source.strategy.cached()) /
                source.strategy.totalSupply();
        }
    }

    function get(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amount
    ) external view returns (uint256 value, uint256 updateTime) {
        return _peek(baseId.b6(), quoteId.b6(), amount);
    }
}
