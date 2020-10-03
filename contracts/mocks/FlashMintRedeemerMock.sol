// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IFlashMinter.sol";
import "../interfaces/IFYDai.sol";


contract FlashMintRedeemerMock is IFlashMinter {

    event Parameters(address user, uint256 amount, bytes data);

    uint256 public flashBalance;

    function executeOnFlashMint(address to, uint256 fyDaiAmount, bytes calldata data) external override {
        flashBalance = IFYDai(msg.sender).balanceOf(address(this));
        IFYDai(msg.sender).redeem(address(this), address(this), flashBalance);
        emit Parameters(to, fyDaiAmount, data);
    }

    function flashMint(address fyDai, uint256 amount, bytes calldata data) public {
        IFYDai(fyDai).flashMint(address(this), amount, data);
    }
}