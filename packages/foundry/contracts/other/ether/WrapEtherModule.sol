// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "../../LadleStorage.sol";


/// @dev Module to allow the Ladle to wrap Ether into WETH and transfer it to any destination
contract WrapEtherModule is LadleStorage {
    using TransferHelper for IERC20;

    constructor (ICauldron cauldron, IWETH9 weth) LadleStorage(cauldron, weth) { }

    /// @dev Allow users to wrap Ether in the Ladle and send it to any destination.
    function wrap(address receiver, uint256 wad)
        external payable
    {
        weth.deposit{ value: wad }();
        IERC20(address(weth)).safeTransfer(receiver, wad);
    }
}