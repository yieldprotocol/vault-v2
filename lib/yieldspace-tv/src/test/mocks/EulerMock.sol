// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;
import {IERC20Metadata} from "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import {TransferHelper} from "@yield-protocol/utils-v2/src/token/TransferHelper.sol";

/// @notice This contract mimics the Euler router
contract EulerMock {
    using TransferHelper for IERC20Metadata;

    /// @notice Use Euler to move tokens
    function move(IERC20Metadata token, address from, address to, uint256 amount) external {
        token.safeTransferFrom(from, to, amount);
    }
}
