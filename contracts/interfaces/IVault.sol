pragma solidity ^0.6.2;


interface IVault {
    function posted(address) external returns (uint256);
    function settle(uint256, address) external returns (uint256, uint256, uint256);
    function grab(address, uint256) external;
}