pragma solidity ^0.6.2;


interface IVault {
    function settle(uint256, address) external returns (uint256, uint256);
    function grab(address) external returns (uint256);
}