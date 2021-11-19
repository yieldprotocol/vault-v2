// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "./IUniswapV3PoolImmutables.sol";
// This for the real deal
// import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "../../mocks/oracles/uniswap/UniswapV3OracleLibraryMock.sol";

/**
 * @title UniswapV3Oracle
 */
contract UniswapV3Oracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed base, bytes6 indexed quote, address indexed source, uint32 secondsAgo);

    struct Source {
        address source;
        bool inverse;
    }

    struct SourceData {
        address factory;
        address baseToken;
        address quoteToken;
        uint24 fee;
        uint32 secondsAgo;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;
    mapping(address => SourceData) public sourcesData;

    /**
     * @notice Set or reset an oracle source & its inverse and secondsAgo
     */
    function setSource(bytes6 base, bytes6 quote, address source,uint32 secondsAgo) external auth {
        require(secondsAgo != 0, 'Uniswap must look into the past.');
        _setSource(base, quote, source,secondsAgo);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function peek(bytes32 base, bytes32 quote, uint256 amount)
        external view virtual override
        returns (uint256 value, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), amount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     */
    function get(bytes32 base, bytes32 quote, uint256 amount)
        external virtual override
        returns (uint256 value, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), amount);
    }

    function _peek(bytes6 base, bytes6 quote, uint256 amount)
        private view
        returns (uint256 value, uint256 updateTime)
    {
        Source memory source = sources[base][quote];
        SourceData memory sourceData;
        require(source.source != address(0), "Source not found");
        sourceData = sourcesData[source.source];
        if (source.inverse) {
            value = UniswapV3OracleLibraryMock.consult(sourceData.factory, sourceData.quoteToken, sourceData.baseToken, sourceData.fee, amount, sourceData.secondsAgo);
        } else {
            value = UniswapV3OracleLibraryMock.consult(sourceData.factory, sourceData.baseToken, sourceData.quoteToken, sourceData.fee, amount, sourceData.secondsAgo);
        }
        updateTime = block.timestamp - sourceData.secondsAgo;
    }

    function _setSource(bytes6 base, bytes6 quote, address source,uint32 secondsAgo) internal {
        sources[base][quote] = Source(source, false);
        sources[quote][base] = Source(source, true);
        sourcesData[source] = SourceData(
            IUniswapV3PoolImmutables(source).factory(),
            IUniswapV3PoolImmutables(source).token0(),
            IUniswapV3PoolImmutables(source).token1(),
            IUniswapV3PoolImmutables(source).fee(),
            secondsAgo
        );
        emit SourceSet(base, quote, source, secondsAgo);
        emit SourceSet(quote, base, source, secondsAgo);
    }
}