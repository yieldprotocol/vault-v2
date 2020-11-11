// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IWeth is IERC20 {
    function deposit() external payable;
    function withdraw(uint) external;
}