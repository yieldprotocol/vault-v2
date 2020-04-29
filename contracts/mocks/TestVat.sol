pragma solidity ^0.6.2;

import "./../interfaces/IVat.sol";


contract TestVat is IVat {
    uint256 internal _rate;

    function frob(bytes32, address, address, address, int, int)
        external override
    {}

    function ilks(bytes32)
        external view override returns
    (
        uint256,   // wad
        uint256 rate,  // ray
        uint256,  // ray
        uint256,  // rad
        uint256   // rad
    ){
        rate = _rate;
    }

    function urns(bytes32, address)
        external view override returns (uint, uint)
    {}


    function set(uint256 rate_) public {
        _rate = rate_;
    }
}