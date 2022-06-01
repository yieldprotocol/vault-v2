// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "../../oracles/lido/IWstETH.sol";

/// @dev A contract to handle wrapping & unwrapping of stETH
contract StEthConverter {
    using TransferHelper for IERC20;
    using TransferHelper for IWstETH;

    IWstETH public immutable wstETH;
    IERC20 public immutable stETH;

    constructor(IWstETH wstETH_, IERC20 stETH_) {
        wstETH = wstETH_;
        stETH = stETH_;
        stETH_.approve(address(wstETH_), type(uint256).max);
    }

    /// @dev Wrap stEth held by this contract and forward it to the "to" address
    function wrap(address to) external returns (uint256 wstEthAmount) {
        uint256 stEthAmount = stETH.balanceOf(address(this));
        wstEthAmount = wstETH.wrap(stEthAmount);
        wstETH.safeTransfer(to, wstEthAmount);
    }

    /// @dev Unwrap WstETH held by this contract, and send the stETH to the "to" address
    function unwrap(address to) external returns (uint256 stEthAmount) {
        uint256 wstEthAmount = wstETH.balanceOf(address(this));
        stEthAmount = wstETH.unwrap(wstEthAmount);
        stETH.safeTransfer(to, stEthAmount);
    }
}
