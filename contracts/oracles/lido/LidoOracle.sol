// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import '@yield-protocol/utils-v2/contracts/access/AccessControl.sol';
import '@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol';
import '@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol';
import '@yield-protocol/vault-interfaces/IOracle.sol';
import '../../constants/Constants.sol';
import './IWstETH.sol';

/**
 * @title LidoOracle
 * @notice
 */
contract LidoOracle is IOracle, AccessControl, Constants {
    using CastBytes32Bytes6 for bytes32;
    IWstETH iwstETH;
    bytes32 public WstETH = 0x3035000000000000000000000000000000000000000000000000000000000000;

    function setSource(IWstETH wstETH_) external auth {
        iwstETH = wstETH_;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
    }

    function _peek(
        bytes6 base,
        bytes6 quote,
        uint256 amount
    ) private view returns (uint256 value, uint256 updateTime) {
        require(base == WstETH || quote == WstETH, 'Source not found');
        if (base == WstETH) {
            //Base equals WstETH
            value = iwstETH.getStETHByWstETH(amount);
        } else if (quote == WstETH) {
            //Base equals stETH
            value = iwstETH.getWstETHByStETH(amount);
        }
        updateTime = block.timestamp;
    }
}
