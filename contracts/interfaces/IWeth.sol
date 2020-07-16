// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


interface IWeth {
    function deposit() external payable;
    function withdraw(uint) external;
    function approve(address, uint) external returns (bool) ;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}