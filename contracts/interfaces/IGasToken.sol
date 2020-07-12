// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.10;


/// @dev interface for the GasToken1 contract
/// Taken from https://github.com/makerdao/developerguides/blob/master/dai/dsr-integration-guide/dsr.sol
interface IGasToken {
    function mint(uint value) external;
    function free(uint256 value) external returns (bool success);
    function transfer(address to, uint256 value) external returns (bool success);
    function transferFrom(address from, address to, uint256 value) external returns (bool success);
    function allowance(address owner, address spender) external view returns (uint256 remaining);
    function balanceOf(address owner) external view returns (uint256 balance);
}