// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/AllTransferHelper.sol";


contract TransferModule is AccessControl() {
    using AllTransferHelper for IERC20;

    /// @dev Transfer `wad` of `token` from `src` to `dst`
    function transferFrom(address initiator, bytes memory data)
        external
        auth
    {
        (address token, address dst, uint256 wad) = abi.decode(data, (address, address, uint256));
        IERC20(token).safeTransferFrom(initiator, dst, wad);
    }
}