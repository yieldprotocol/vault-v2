pragma solidity ^0.6.2;


interface IVault {
    function series(uint256) external returns (address);
    function systemDebt() external returns (uint256);
    function posted(bytes32, address) external returns (uint256);
    function totalDebtYDai(bytes32, address) external returns (uint256);
    function erase(bytes32, address) external returns (uint256, uint256);
}