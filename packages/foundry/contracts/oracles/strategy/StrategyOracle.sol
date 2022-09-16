// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "../../interfaces/IOracle.sol";

interface IStrategy {
    /// @notice Explain to an end user what this does
    /// @return Documents the return variables of a contract’s function state variable
    function cached() external view returns (uint256);

    /// @notice Explain to an end user what this does
    /// @return Documents the return variables of a contract’s function state variable
    function totalSupply() external view returns (uint256);
}

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
        uint8 decimals;
        bool inverse;
        IStrategy strategy;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    function setSource(
        bytes6 baseId,
        bytes6 quoteId,
        uint8 decimals,
        IStrategy strategy
    ) external auth {
        sources[baseId][quoteId] = Source({
            strategy: strategy,
            decimals: decimals,
            inverse: false
        });
        emit SourceSet(baseId, quoteId, strategy);
        if (baseId != quoteId) {
            sources[quoteId][baseId] = Source({
                strategy: strategy,
                decimals: decimals,
                inverse: true
            });
            emit SourceSet(quoteId, baseId, strategy);
        }
    }

    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
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
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
    }
}
