// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "../../interfaces/IOracle.sol";

interface IRocketTokenRETH {
    // Calculate the amount of rETH backed by an amount of ETH
    function getRethValue(uint256 _ethAmount) external view returns (uint256);

    // Calculate the amount of ETH backing an amount of rETH
    function getEthValue(uint256 _rethAmount) external view returns (uint256);
}

contract RETHOracle is IOracle {
    using Cast for bytes32;

    bytes6 immutable ethId;
    bytes6 immutable rEthId;
    IRocketTokenRETH immutable rEth;

    event SourceSet(bytes6 ethId, bytes6 rEthId, IRocketTokenRETH indexed rEth);

    constructor(
        bytes6 ethId_,
        bytes6 rEthId_,
        IRocketTokenRETH rEth_
    ) {
        ethId = ethId_;
        rEthId = rEthId_;
        rEth = rEth_;

        emit SourceSet(ethId, rEthId, rEth);
    }

    /**
     * @notice Doesn't refresh the price, but returns the latest value available without doing any transactional operations
     * @param base The asset in which the `amount` to be converted is represented
     * @param quote The asset in which the converted `value` will be represented
     * @param baseAmount The amount to be converted from `base` to `quote`
     * @return value The converted value of `amount` from `base` to `quote`
     * @return updateTime The timestamp when the conversion price was taken
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    ) external view returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Does whatever work or queries will yield the most up-to-date price, and returns it.
     * @param base The asset in which the `amount` to be converted is represented
     * @param quote The asset in which the converted `value` will be represented
     * @param baseAmount The amount to be converted from `base` to `quote`
     * @return value The converted value of `amount` from `base` to `quote`
     * @return updateTime The timestamp when the conversion price was taken
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    ) external view returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function _peek(
        bytes6 base,
        bytes6 quote,
        uint256 baseAmount
    ) private view returns (uint256 quoteAmount, uint256 updateTime) {
        require(
            (base == rEthId && quote == ethId) ||
                (base == ethId && quote == rEthId),
            "Source not found"
        );

        if (base == rEthId) {
            quoteAmount = rEth.getEthValue(baseAmount);
        } else if (quote == rEthId) {
            quoteAmount = rEth.getRethValue(baseAmount);
        }

        updateTime = block.timestamp;
    }
}
