pragma solidity ^0.6.10;

import "../interfaces/IFlashMinter.sol";
import "../interfaces/IYDai.sol";


contract FlashMinterMock is IFlashMinter {

    event Parameters(address user, uint256 amount, bytes32 data);

    uint256 public flashBalance;

    function executeOnFlashMint(address to, uint256 yDaiAmount, bytes32 data) external override {
        flashBalance = IYDai(msg.sender).balanceOf(address(this));
        emit Parameters(to, yDaiAmount, data);
    }

    function flashMint(address yDai, uint256 amount, bytes32 data) public {
        IYDai(yDai).flashMint(address(this), amount, data);
    }
}