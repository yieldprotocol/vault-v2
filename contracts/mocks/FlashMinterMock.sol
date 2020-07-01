pragma solidity ^0.6.2;

import "../interfaces/IFlashMinter.sol";
import "../interfaces/IYDai.sol";


contract FlashMinterMock is IFlashMinter {

    uint256 public flashBalance;

    function executeOnFlashMint() external override {
        flashBalance = IYDai(msg.sender).balanceOf(address(this));
    }

    function flashMint(address yDai, uint256 amount) public {
        IYDai(yDai).flashMint(address(this), amount);
    }
}