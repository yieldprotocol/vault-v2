// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDelegable.sol";
import "./IERC2612.sol";
import "./IYDai.sol";

interface IPool is IDelegable, IERC20, IERC2612 {
    function dai() external view returns(IERC20);
    function yDai() external view returns(IYDai);
    function sellDai(address from, address to, uint128 daiIn) external returns(uint128);
    function buyDai(address from, address to, uint128 daiOut) external returns(uint128);
    function sellYDai(address from, address to, uint128 yDaiIn) external returns(uint128);
    function buyYDai(address from, address to, uint128 yDaiOut) external returns(uint128);
    function sellDaiPreview(uint128 daiIn) external view returns(uint128);
    function buyDaiPreview(uint128 daiOut) external view returns(uint128);
    function sellYDaiPreview(uint128 yDaiIn) external view returns(uint128);
    function buyYDaiPreview(uint128 yDaiOut) external view returns(uint128);
}