// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IFlashMinter.sol";
import "../interfaces/IEDai.sol";


contract FlashMintRedeemerMock is IFlashMinter {

    event Parameters(address user, uint256 amount, bytes data);

    uint256 public flashBalance;

    function executeOnFlashMint(address to, uint256 eDaiAmount, bytes calldata data) external override {
        flashBalance = IEDai(msg.sender).balanceOf(address(this));
        IEDai(msg.sender).redeem(address(this), address(this), flashBalance);
        emit Parameters(to, eDaiAmount, data);
    }

    function flashMint(address eDai, uint256 amount, bytes calldata data) public {
        IEDai(eDai).flashMint(address(this), amount, data);
    }
}