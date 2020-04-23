pragma solidity ^0.5.2;

import "./../interfaces/IPot.sol";


contract TestPot is Pot {
    function set(uint256 chi_) public {
        chi = chi_;
    }
}