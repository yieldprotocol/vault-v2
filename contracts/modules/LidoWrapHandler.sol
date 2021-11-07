// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import '@yield-protocol/utils-v2/contracts/token/IERC20.sol';
import '@yield-protocol/utils-v2/contracts/token/TransferHelper.sol';
import '../LadleStorage.sol';
import '../oracles/lido/IWstETH.sol';

/// @dev A contract to handle wrapping & unwrapping of stETH
contract LidoWrapHandler {
    using TransferHelper for IERC20;
    using TransferHelper for IWstETH;

    IWstETH public immutable wstETH;
    IERC20 public immutable stETH;

    /// @dev The amount of stETH wrapped
    event Wrapped(address to, uint256 amount);

    /// @dev The amount of wstETH unwrapped
    event Unwrapped(address to, uint256 amount);

    constructor(IWstETH wstETH_, IERC20 stETH_) {
        wstETH = wstETH_;
        stETH = stETH_;
    }

    /// @dev Wrap stEth held by this contract and forward it to the 'to' address
    function wrap(address to) external returns (uint256 wrappedAmount) {
        uint256 stEthTransferred = stETH.balanceOf(address(this));
        require(stEthTransferred > 0, 'No stETH to wrap');
        stETH.approve(address(wstETH), stEthTransferred);
        wrappedAmount = wstETH.wrap(stEthTransferred);
        wstETH.safeTransfer(to, wrappedAmount);
        emit Wrapped(to, wrappedAmount);
    }

    /// @dev Unwrap WstETH held by this contract, and send the stETH to the 'to' address
    function unwrap(address to) external returns (uint256 unwrappedAmount) {
        uint256 wstEthTransferred = wstETH.balanceOf(address(this));
        require(wstEthTransferred > 0, 'No wstETH to unwrap');
        unwrappedAmount = wstETH.unwrap(wstEthTransferred);
        stETH.safeTransfer(to, unwrappedAmount);
        emit Unwrapped(to, unwrappedAmount);
    }
}
