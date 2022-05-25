// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/vault-interfaces/src/IOracle.sol";
import "./IWstETH.sol";

/**
 * @title LidoOracle
 * @notice Oracle to fetch WstETH-stETH exchange amounts
 */
contract LidoOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    IWstETH public wstETH;
    bytes32 public immutable wstEthId;
    bytes32 public immutable stEthId;

    event SourceSet(IWstETH wstETH);

    constructor(bytes32 wstEthId_, bytes32 stEthId_) {
        wstEthId = wstEthId_;
        stEthId = stEthId_;
    }

    /**
     * @notice Set the source for fetching the price from. It should be the wstETH contract.
     */
    function setSource(IWstETH wstETH_) external auth {
        wstETH = wstETH_;
        emit SourceSet(wstETH_);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `wstEthId` and `stEthId` are accepted as asset identifiers.
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    ) external view virtual override returns (uint256 quoteAmount, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     * Only `wstEthId` and `stEthId` are accepted as asset identifiers.
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    ) external virtual override returns (uint256 quoteAmount, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }


    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `wstEthId` and `stEthId` are accepted as asset identifiers.
     */
    function _peek(
        bytes6 base,
        bytes6 quote,
        uint256 baseAmount
    ) private view returns (uint256 quoteAmount, uint256 updateTime) {
        require((base == wstEthId && quote == stEthId) || (base == stEthId && quote == wstEthId), "Source not found");

        if (base == wstEthId) {
            //Base equals WstETH
            quoteAmount = wstETH.getStETHByWstETH(baseAmount);
        } else if (quote == wstEthId) {
            //Base equals stETH
            quoteAmount = wstETH.getWstETHByStETH(baseAmount);
        }
        updateTime = block.timestamp;
    }
}
