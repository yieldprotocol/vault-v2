// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/IOracle.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "uniswapv3-oracle/contracts/uniswapv0.8/OracleLibrary.sol";
import "uniswapv3-oracle/contracts/uniswapv0.8/pool/IUniswapV3PoolImmutables.sol";

/**
 * @title UniswapV3Oracle
 */
contract UniswapV3Oracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    using CastU256U128 for uint256;

    event SourceSet(bytes6 indexed base, bytes6 indexed quote, address indexed pool, uint32 twapInterval);

    struct Source {
        address pool;
        address baseToken;
        address quoteToken;
        uint32 twapInterval;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /**
     * @notice Set or reset an oracle source, its inverse and twapInterval
     */
    function setSource(bytes6 base, bytes6 quote, address pool, uint32 twapInterval) external auth {
        require(twapInterval != 0, "Uniswap must look into the past.");
        _setSource(base, quote, pool, twapInterval);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function peek(bytes32 base, bytes32 quote, uint256 amountBase)
        external view virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), amountBase);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     */
    function get(bytes32 base, bytes32 quote, uint256 amountBase)
        external virtual override
        returns (uint256 amountQuote, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), amountBase);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function _peek(bytes6 base, bytes6 quote, uint256 amountBase)
        private view
        returns (uint256 amountQuote, uint256 updateTime)
    {
        Source memory source = sources[base][quote];
        require(source.pool != address(0), "Source not found");
        int24 twapTick = OracleLibrary.consult(source.pool, source.twapInterval);
        amountQuote = OracleLibrary.getQuoteAtTick(
            twapTick,
            amountBase.u128(),
            source.baseToken,
            source.quoteToken
        );
        updateTime = block.timestamp - source.twapInterval;
    }

    /**
     * @notice Set or reset an oracle source, its inverse and twapInterval
     */
    function _setSource(bytes6 base, bytes6 quote, address pool, uint32 twapInterval) internal {
        sources[base][quote] = Source(
            pool,
            IUniswapV3PoolImmutables(pool).token0(),
            IUniswapV3PoolImmutables(pool).token1(),
            twapInterval        
        );
        sources[quote][base] = Source(
            pool,
            IUniswapV3PoolImmutables(pool).token1(),
            IUniswapV3PoolImmutables(pool).token0(),
            twapInterval        
        );
        emit SourceSet(base, quote, pool, twapInterval);
        emit SourceSet(quote, base, pool, twapInterval);
    }
}