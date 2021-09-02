// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "../../constants/Constants.sol";
import "./CTokenInterface.sol";


contract CTokenMultiOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, address indexed source);

    struct Source {
        address source;
        uint8 decimals;
        bool inverse;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /**
     * @notice Set or reset an oracle source and its inverse
     */
    function setSource(bytes6 cTokenId, bytes6 underlying, address cToken) external auth {
        _setSource(cTokenId, underlying, cToken);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function peek(bytes32 base, bytes32 quote, uint256 amountIn)
        external view virtual override
        returns (uint256 amountOut, uint256 updateTime)
    {
        uint256 rawPrice;
        uint8 decimals_ = 18; // TODO: This should be the decimals of the token (i.e, 6 for USDC)
        Source memory source = sources[base.b6()][quote.b6()];
        require (source.source != address(0), "Source not found");

        rawPrice = CTokenInterface(source.source).exchangeRateStored();
        require(rawPrice > 0, "Compound price is zero");
        uint256 price = _scale(rawPrice, source.decimals, decimals_);

        // If calculating the inverse, we divide 1 (with the decimals of this oracle) by the price
        if (source.inverse == true) price = (10 ** (uint256(decimals_) * 2)) / uint(price);

        amountOut = price * amountIn / 1e18;
        updateTime = block.timestamp; // TODO: We should get the timestamp
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Updates the price before fetching it if possible.
     */
    function get(bytes32 base, bytes32 quote, uint256 amountIn)
        external virtual override
        returns (uint256 amountOut, uint256 updateTime)
    {
        uint256 rawPrice;
        uint8 decimals_ = 18; // TODO: This should be the decimals of the token (i.e, 6 for USDC)
        Source memory source = sources[base.b6()][quote.b6()];
        require (source.source != address(0), "Source not found");

        rawPrice = CTokenInterface(source.source).exchangeRateCurrent();
        require(rawPrice > 0, "Compound price is zero");
        uint256 price = _scale(rawPrice, source.decimals, decimals_);

        // If calculating the inverse, we divide 1 (with the decimals of this oracle) by the price
        if (source.inverse == true) price = (10 ** (uint256(decimals_) * 2)) / uint(price);

        amountOut = price * amountIn / 1e18;
        updateTime = block.timestamp; // TODO: We should get the timestamp
    }

    /**
     * @notice Convert a price between two decimal bases
     * @dev The castings in this code won't overflow
     */
    function _scale(uint256 rawPrice, uint8 sourceDecimals, uint8 oracleDecimals)
        private pure
        returns (uint256 price)
    {
        // We scale the source data to the decimals of this oracle
        int256 diff = int256(uint256(sourceDecimals)) - int256(uint256(oracleDecimals));
        if (diff >= 0) price = uint(rawPrice) / 10 ** uint256(diff);
        else price = uint(rawPrice) * 10 ** uint256(-diff);
    }

    /**
     * @dev Set a cToken as a data source between said cToken and its underlying, and its inverse
     */
    function _setSource(bytes6 cTokenId, bytes6 underlying, address source) internal {
        uint8 decimals_ = IERC20Metadata(CTokenInterface(source).underlying()).decimals() + 10; // https://compound.finance/docs/ctokens#exchange-rate
        sources[cTokenId][underlying] = Source({
            source: source,
            decimals: decimals_,
            inverse: false
        });
        sources[underlying][cTokenId] = Source({
            source: source,
            decimals: decimals_,
            inverse: true
        });
        emit SourceSet(cTokenId, underlying, source);
        emit SourceSet(underlying, cTokenId, source);
    }
}