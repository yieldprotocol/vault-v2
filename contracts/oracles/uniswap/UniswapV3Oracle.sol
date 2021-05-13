// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@yield-protocol/utils-v2/contracts/access/Ownable.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "../../math/CastBytes32Bytes6.sol";
import "./IUniswapV3PoolImmutables.sol";
// This for the real deal
// import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "../../mocks/UniswapV3OracleLibraryMock.sol";

/**
 * @title UniswapV3Oracle
 */
contract UniswapV3Oracle is IOracle, Ownable {
    using CastBytes32Bytes6 for bytes32;

    event SecondsAgoSet(uint32 indexed secondsAgo);
    event SourcesSet(bytes6[] indexed bases, bytes6[] indexed quotes, address[] indexed sources_);

    struct SourceData {
        address factory;
        address baseToken;
        address quoteToken;
        uint24 fee;
    }

    uint32 public secondsAgo;
    mapping(bytes6 => mapping(bytes6 => address)) public sources;
    mapping(address => SourceData) public sourcesData;

    /**
     * @notice Set or reset the number of seconds Uniswap will use for its Time Weighted Average Price computation
     */
    function setSecondsAgo(uint32 secondsAgo_) public onlyOwner {
        require(secondsAgo_ != 0, "Uniswap must look into the past.");
        secondsAgo = secondsAgo_;
        emit SecondsAgoSet(secondsAgo_);
    }

    /**
     * @notice Set or reset a number of oracle sources
     */
    function setSources(bytes6[] memory bases, bytes6[] memory quotes, address[] memory sources_) public onlyOwner {
        require(bases.length == quotes.length && quotes.length == sources_.length, "Mismatched inputs");
        for (uint256 i = 0; i < bases.length; i++) {
            sources[bases[i]][quotes[i]] = sources_[i];
            sourcesData[sources_[i]] = SourceData(
                IUniswapV3PoolImmutables(sources_[i]).factory(),
                IUniswapV3PoolImmutables(sources_[i]).token0(),
                IUniswapV3PoolImmutables(sources_[i]).token1(),
                IUniswapV3PoolImmutables(sources_[i]).fee()
            );
        }
        emit SourcesSet(bases, quotes, sources_);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * @return value
     */
    function peek(bytes32 base, bytes32 quote, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        SourceData memory sourceData = sourcesData[sources[base.b6()][quote.b6()]];
        value = UniswapV3OracleLibraryMock.consult(sourceData.factory, sourceData.baseToken, sourceData.quoteToken, sourceData.fee, amount, secondsAgo);
        updateTime = block.timestamp - secondsAgo;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.. Same as `peek` for this oracle.
     * @return value
     */
    function get(bytes32 base, bytes32 quote, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        return peek(base, quote, amount);
    }
}
