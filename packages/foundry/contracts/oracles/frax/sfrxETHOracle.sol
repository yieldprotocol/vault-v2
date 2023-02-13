// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "../../interfaces/IOracle.sol";

/**
 * @title SfrxETHOracle
 * @notice Oracle to fetch sfrxETH-frax exchange amounts
 */
contract SfrxETHOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    SfrxEthDualOracleChainlinkUniV3 public source;
    bytes32 public immutable sfrxEthId;
    bytes32 public immutable fraxId;

    event SourceSet(SfrxEthDualOracleChainlinkUniV3 sfrxETHOracle);

    constructor(bytes32 sfrxEthId_, bytes32 fraxId_) {
        sfrxEthId = sfrxEthId_;
        fraxId = fraxId_;
    }

    /**
     * @notice Set the source for fetching the price from. It should be the frax/sfrxETH oracle contract.
     */
    function setSource(SfrxEthDualOracleChainlinkUniV3 source_) external auth {
        source = source_;
        emit SourceSet(source_);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `sfrxEthId` and `fraxId` are accepted as asset identifiers.
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    )
        external
        view
        virtual
        override
        returns (uint256 quoteAmount, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     * Only `sfrxEthId` and `fraxId` are accepted as asset identifiers.
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    )
        external
        virtual
        override
        returns (uint256 quoteAmount, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `sfrxEthId` and `fraxId` are accepted as asset identifiers.
     */
    function _peek(
        bytes6 base,
        bytes6 quote,
        uint256 baseAmount
    ) private view returns (uint256 quoteAmount, uint256 updateTime) {
        require(
            (base == sfrxEthId && quote == fraxId) ||
                (base == sfrxEthId && quote == fraxId),
            "Source not found"
        );

        (, _priceLow, ) = source.getPrices(); // the price of frax to sfrxETH;

        if (base == sfrxEthId) {
            // Base equals sfrxETH, so quote is frax
            // convert appropriately for sfrxETH as base using inverse of source price
            quoteAmount = (baseAmount * 1e18) / _priceLow;
        } else if (quote == sfrxETH) {
            // Base equals frax, so quote is sfrxETH
            quoteAmount = _priceLow * baseAmount;
        }
        updateTime = block.timestamp;
    }
}
