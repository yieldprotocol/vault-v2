// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


/// @dev interface for the pot contract from MakerDao
/// Taken from https://github.com/makerdao/developerguides/blob/master/dai/dsr-integration-guide/dsr.sol
interface IJug {
    function ilks(bytes32) external returns (uint256, uint256);
    function drip(bytes32) external returns (uint256);
}