// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "./IV1FYDai.sol";

interface IV1Pool is IERC20 {
    function dai() external view returns(IERC20);
    function fyDai() external view returns(IV1FYDai);
    function sellFYDai(address from, address to, uint128 fyDaiIn) external returns(uint128);
    function burn(address from, address to, uint256 tokensBurned) external returns (uint256, uint256);
}