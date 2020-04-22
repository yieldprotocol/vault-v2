pragma solidity ^0.5.2;

import "./../IVat.sol";

contract TestVat is Vat {
    uint256 _rate;

    function ilks(bytes32) external view returns (
        uint256 Art,   // wad
        uint256 rate,  // ray
        uint256 spot,  // ray
        uint256 line,  // rad
        uint256 dust   // rad
    ){
        rate = _rate;
    }

    function set(uint256 newRate) public {
        _rate = newRate;
    }

}