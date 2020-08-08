// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IPool.sol";
import "../interfaces/IController.sol";
import "../interfaces/IChai.sol";
import "@openzeppelin/contracts/math/Math.sol";
/**
 * @dev The LiquidityProxy is a proxy contract of Pool that allows users to mint liquidity tokens with just Dai. 
 */
contract LiquidityProxy {
    uint256 constant public ONE = 1000000000000000000;
    IController public controller;
    IChai public chai;

    /// @dev The constructor links ControllerDai to vat, pot, controller and pool.
    constructor (
        address controller_,
        address chai_
    ) public {
        _vat = IVat(vat_);
        _dai = IERC20(dai_);
        _pot = IPot(pot_);
        _yDai = IERC20(yDai_);
        _controller = IController(controller_);
        _pool = IPool(pool_);


    }

    /// @dev Overflow-protected addition, from OpenZeppelin
    function add(uint128 a, uint128 b)
        internal pure returns (uint128)
    {
        uint128 c = a + b;
        require(c >= a, "Liquidity Proxy: add overflow");

        return c;
    }

    /// @dev Overflow-protected substraction, from OpenZeppelin
    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        require(b <= a, "Liquidity Proxy: sub overflow");
        uint128 c = a - b;

        return c;
    }

    /// @dev Overflow-protected addition, from DappHub
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    /// @dev Divides x by y, where x and y are fixed point with 18 decimals
    function div(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, ONE) / y;
    }

    // @dev mints liquidity with provided Dai by borrowing yDai with some of the Dai
    /// @param daiUsed Amount of `dai` to use in minting liquidity tokens
    /// @return The amount of liquidity tokens minted.  
     
    function addLiquidity(address from, address pool_, uint256 daiUsed) external
    {
        IPool pool = IPool(pool_);
        IERC20 dai = pool.dai;
        IYDai yDai = pool.yDai;
        uint256 daiReserves = dai.balanceOf(pool_);
        uint256 yDaiReserves = yDai.balanceOf(pool_);
        uint256 divisor = ONE.add(div(yDaiReserves, daiReserves));
        uint256 daiToAdd = div(daiUsed, divisor);
        uint256 DaiToChai = sub(daiUsed, daiToAdd);
        // borrow yDai
        require(dai.transferFrom(fromr, address(this), DaiToChai));
        chai.join(address(this), DaiToChai);
        controller.post(CHAI, msg.sender, msg.sender, amount);
        controller.borrow(CHAI, yDai.maturity, address(this), address(this), DaiToChai);
        pool.mint(daiToAdd);
    }

}