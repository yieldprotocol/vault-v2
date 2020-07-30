// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


interface ILiquidations {
    function shutdown() external;
    function totals() external view returns(uint128, uint128);
    function erase(address) external returns(uint128, uint128);
}