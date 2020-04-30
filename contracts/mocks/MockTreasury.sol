pragma solidity ^0.6.2;

import "./../Treasury.sol";


contract MockTreasury is Treasury {

    function borrowDai(address receiver, uint256 amount) public {
        _borrowDai(receiver, amount);
    }

    function repayDai() public {
        _repayDai();
    }

    function lockDai() public {
        _lockDai();
    }

    function freeDai(uint256 amount) public {
        _freeDai(amount);
    }
}
