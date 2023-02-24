// SPDX-License-Identifier: MIT
// Taken from https://github.com/Uniswap/uniswap-lib/blob/master/src/libraries/TransferHelper.sol
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "../utils/RevertMsgExtractor.sol";

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
// USDT is a well known token that returns nothing for its transfer, transferFrom, and approve functions
// and part of the reason this library exists
library TransferHelper {
    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Errors with the underlying revert message if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        if (!(success && _returnTrueOrNothing(data))) revert(RevertMsgExtractor.getRevertMsg(data));
    }

    /// @notice Approves a spender to transfer tokens from msg.sender
    /// @dev Errors with the underlying revert message if transfer fails
    /// @param token The contract address of the token which will be approved
    /// @param spender The approved spender
    /// @param value The value of the allowance
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.approve.selector, spender, value));
        if (!(success && _returnTrueOrNothing(data))) revert(RevertMsgExtractor.getRevertMsg(data));
    }

    /// @notice Transfers tokens from the targeted address to the given destination
    /// @dev Errors with the underlying revert message if transfer fails
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        if (!(success && _returnTrueOrNothing(data))) revert(RevertMsgExtractor.getRevertMsg(data));
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Errors with the underlying revert message if transfer fails
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address payable to, uint256 value) internal {
        (bool success, bytes memory data) = to.call{value: value}(new bytes(0));
        if (!success) revert(RevertMsgExtractor.getRevertMsg(data));
    }

    function _returnTrueOrNothing(bytes memory data) internal pure returns(bool) {
        return (data.length == 0 || abi.decode(data, (bool)));
    }
}
