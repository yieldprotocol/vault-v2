// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.10;


interface IFlashMinter {
    function executeOnFlashMint(address to, uint256 yDaiAmount, bytes calldata data) external;
}