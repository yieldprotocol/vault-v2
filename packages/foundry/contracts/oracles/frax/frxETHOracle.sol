// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC4626.sol";
import "../../interfaces/IOracle.sol";

/**
 * @title FrxETHOracle
 * @notice Oracle to fetch sfrxETH-frxETH exchange amounts
 */
contract FrxETHOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    IERC4626 public sfrxETH;
    bytes32 public immutable sfrxEthId;
    bytes32 public immutable frxEthId;

    event SourceSet(ISfrxETH sfrxETH);

    constructor(bytes32 sfrxEthId_, bytes32 frxETHId_) {
        sfrxEthId = sfrxEthId_;
        frxEthId = frxEthId;
    }

    /**
     * @notice Set the source for fetching the price from. It should be the sfrxETH contract.
     */
    function setSource(ISfrxETH sfrxETH_) external auth {
        sfrxETH = sfrxETH_;
        emit SourceSet(sfrxETH_);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `sfrxEthId` and `frxEthId` are accepted as asset identifiers.
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
     * Only `sfrxEthId` and `frxEthId` are accepted as asset identifiers.
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
     * Only `sfrxEthId` and `frxEthId` are accepted as asset identifiers.
     */
    function _peek(
        bytes6 base,
        bytes6 quote,
        uint256 baseAmount
    ) private view returns (uint256 quoteAmount, uint256 updateTime) {
        require(
            (base == sfrxEthId && quote == frxEthId) ||
                (base == frxEthId && quote == sfrxEthId),
            "Source not found"
        );

        if (base == sfrxEthId) {
            // Base equals sfrxETH
            quoteAmount = sfrxETH.previewRedeem(baseAmount);
        } else if (quote == sfrxEthId) {
            // Base equals frxETH
            quoteAmount = sfrxETH.previewDeposit(baseAmount);
        }
        updateTime = block.timestamp;
    }
}
