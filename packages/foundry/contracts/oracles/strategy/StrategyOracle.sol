// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "../../interfaces/IOracle.sol";
import "./IStrategy.sol";

contract StrategyOracle is AccessControl, IOracle {
    using CastBytes32Bytes6 for bytes32;
    struct Source {
        IStrategy source;
        uint8 decimals;
        bool inverse;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    function setSource(
        bytes6 baseId,
        bytes6 quoteId,
        uint8 decimals,
        IStrategy strategy
    ) external auth {
        sources[baseId][quoteId] = Source({
            source: strategy,
            decimals: decimals,
            inverse: false
        });

        if (baseId != quoteId) {
            sources[quoteId][baseId] = Source({
                source: strategy,
                decimals: decimals,
                inverse: true
            });
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
        require(address(source.source) != address(0), "Source not found");
        if (source.inverse == true) {
            value =
                (amount *
                (source.source.totalSupply() * source.decimals) )/
                    source.source.cached();
        } else {
            value =
                (amount *
                source.source.cached()) / source.source.totalSupply();
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

// value of strategy token =  number of LP tokens in strat(cached)
//                          ---------------------------------------
//                              totalSupply of strategy tokens
// value of 1 LP token = 1 base
