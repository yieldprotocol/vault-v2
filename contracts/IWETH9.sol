// SPDX-License-Identifier: GPL-3.0-or-later
import "@yield-protocol/utils/contracts/token/IERC20.sol";

pragma solidity ^0.8.0;


interface IWETH9 is IERC20 {
    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    function deposit() external payable;
    function withdraw(uint wad) external;
}