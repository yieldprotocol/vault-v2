pragma solidity ^0.6.2;

import "./../interfaces/IPot.sol";


contract TestPot is IPot {
    uint256 internal _chi;  // the Rate Accumulator

    function chi()
        public view override returns (uint256)
    {
        return _chi;
    }

    function pie(address) public view override returns (uint256) {
        return 1;
    } // Not a function, but a public variable.

    function join(uint256) public override {}

    function exit(uint256) public override {}

    function set(uint256 chi_) public {
        _chi = chi_;
    }
}