pragma solidity ^0.6.2;


interface IVault {
    function posted(address) external returns (uint256);
    function series(uint256) external returns (address);
    function systemDebt() external returns (uint256);
    function totalDebtYDai(address) external returns (uint256);
    function erase(address) external returns (uint256, uint256);
}