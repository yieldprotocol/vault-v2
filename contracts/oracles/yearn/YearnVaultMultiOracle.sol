// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";

import "@yield-protocol/vault-interfaces/IOracle.sol";

import "./IYvToken.sol";

// custom errors:
error SetSourceNotNeeded(); // not necessary to set when baseId == quoteId
error SourceNotFound();     // baseId-quoteId not found in sources
error ZeroPrice();          // vault token returned share price of 0

/**
 *@title  YearnVaultMultiOracle
 *@notice Provides current values for Yearn Vault tokens (e.g. yvUSDC/USDC)
 *@dev    Both peek() and get() are provided for convenience
 *        Prices are calculated, never based on cached values
 */
contract YearnVaultMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed source,
        uint8 decimals,
        bool inverse
    );

    struct Source {
        address source;
        uint8 decimals;
        bool inverse;
    }

    /**
     *@notice This is a registry of baseId => quoteId => Source
     *        used to look up the Yearn vault address needed to calculate share price
     */
    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /**
     *@notice Set or reset an oracle source and its inverse
     *@param  baseId id used for related base token (e.g. USDC)
     *@param  vaultTokenId id for Yearn vault token (e.g. yvUSDC)
     *@param  vaultToken address for Yearn vault token
     */
    function setSource(
        bytes6 baseId,
        bytes6 vaultTokenId,
        IERC20Metadata vaultToken
    ) external auth {
        if (baseId == vaultTokenId) {
            revert SetSourceNotNeeded();
        }

        uint8 decimals = vaultToken.decimals();

        _setSource(baseId, vaultTokenId, vaultToken, decimals, false);
        _setSource(vaultTokenId, baseId, vaultToken, decimals, true);
    }

    /**
     *@notice internal function to set source and emit event
     *@param  baseId id used for base token
     *@param  quoteId id for quote (represents vaultToken when inverse == false)
     *@param  source address for vault token used to determine price
     *@param  decimals used by vault token (both source and base)
     *@param  inverse set true for inverse pairs (e.g. USDC/yvUSDC)
     */
    function _setSource(
        bytes6 baseId,
        bytes6 quoteId,
        IERC20Metadata source,
        uint8 decimals,
        bool inverse
    ) internal {
        sources[baseId][quoteId] = Source({source: address(source), decimals: decimals, inverse: inverse});
        emit SourceSet(baseId, quoteId, address(source), decimals, inverse);
    }

    /**
     *@notice External function to convert amountBase base at the current vault share price
     *@dev    This external function calls _get() which calculates current (not cached) price
     *@param  baseId id of base (denominator of rate used)
     *@param  quoteId id of quote (returned amount in this)
     *@param  amountBase amount in base to convert to amount in quote
     *@return amountQuote product of exchange rate and amountBase
     *@return updateTime current block timestamp
     */
    function get(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view override returns (uint256 amountQuote, uint256 updateTime) {
        return _get(baseId.b6(), quoteId.b6(), amountBase);
    }

    /**
     *@notice External function to convert amountBase at the current vault share price
     *@dev    This function is exactly the same as get() and provided as a convenience
     *        for contracts that need to call peek
     */
    function peek(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view override returns (uint256 amountQuote, uint256 updateTime) {
        return _get(baseId.b6(), quoteId.b6(), amountBase);
    }

    /**
     *@notice Used to convert a given amount using the current vault share price
     *@dev    This internal function is called by external functions peek() and get()
     *@param  baseId id of base (denominator of rate used)
     *@param  quoteId id of quote (returned amount converted to this)
     *@param  amountBase amount in base to convert to amount in quote
     *@return amountQuote product of exchange rate and amountBase
     *@return updateTime current block timestamp
     */
    function _get(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amountBase
    ) internal view returns (uint256 amountQuote, uint256 updateTime) {
        updateTime = block.timestamp;

        if (baseId == quoteId) return (amountBase, updateTime);

        Source memory source = sources[baseId][quoteId];
        if (source.source == address(0)) {
            revert SourceNotFound();
        }

        uint256 price = IYvToken(source.source).pricePerShare();
        if (price == 0) {
            revert ZeroPrice();
        }

        if (source.inverse == true) {
            // yvUSDC/USDC: 100 USDC (*10^6) * (10^6 / 1083121 USDC per yvUSDC) = 92325788 yvUSDC wei
            amountQuote = (amountBase * (10**source.decimals)) / price;
        } else {
            // USDC/yvUSDC: 100 yvUSDC (*10^6) * 1083121 USDC per yvUSDC / 10^6 =  108312100 USDC wei
            amountQuote = (amountBase * price) / (10**source.decimals);
        }
    }
}
