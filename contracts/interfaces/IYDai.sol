pragma solidity ^0.6.2;


interface IYDai {
    function isMature() external view returns(bool);
    function maturity() external view returns(uint);
    function chi() external view returns(uint);
    function rate() external view returns(uint);
    function mature() external;
    function mint(address, uint) external;
    function burn(address, uint) external;
    // function transfer(address, uint) external returns (bool);
    // function transferFrom(address, address, uint) external returns (bool);
    // function approve(address, uint) external returns (bool);
}