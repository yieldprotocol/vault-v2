pragma solidity ^0.5.2;


contract Vat {
    function ilks(bytes32) external view returns (
        uint256 Art,   // wad
        uint256 rate,  // ray
        uint256 spot,   // ray
        uint256 line,  // rad
        uint256 dust   // rad
    );
}