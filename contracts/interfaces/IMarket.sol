// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


interface IMarket {
    function sellDai(address from, address to, uint128 daiIn) external returns(uint256);
    function buyDai(address from, address to, uint128 daiOut) external returns(uint256);
    function sellYDai(address from, address to, uint128 yDaiIn) external returns(uint256);
    function buyYDai(address from, address to, uint128 yDaiOut) external returns(uint256);
}