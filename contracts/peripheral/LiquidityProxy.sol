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
    IERC20 public dai;
    IYDai public yDai;
    IPool public pool;

    /// @dev The constructor links ControllerDai to vat, pot, controller and pool.
    constructor (
        address controller_,
        address chai_,
        address dai_,
        address yDai_,
        address pool_,
        address treasury_
    ) public {
        controller = IController(controller_);
        chai = IChai(chai_);
        dai = IERC20(dai_);
        yDai = IYDai(yDai_);
        pool = IPool(pool_);

        dai.approve(address(pool), uint256(-1));
        yDai.approve(address(pool), uint256(-1));
        dai.approve(address(chai), uint256(-1));
        chai.approve(address(treasury_), uint256(-1));
    }

    /// @dev Overflow-protected addition, from OpenZeppelin
    function add(uint256 a, uint256 b)
        internal pure returns (uint256)
    {
        uint256 c = a + b;
        require(c >= a, "Liquidity Proxy: add overflow");

        return c;
    }

    /// @dev Overflow-protected substraction, from OpenZeppelin
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "Liquidity Proxy: sub overflow");
        uint256 c = a - b;

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
     
    function addLiquidity(address from,  uint256 daiUsed) external returns (uint256)
    {
        uint256 daiReserves = dai.balanceOf(address(pool));
        uint256 yDaiReserves = yDai.balanceOf(address(pool));
        uint256 divisor = add(ONE, div(yDaiReserves, daiReserves));
        uint256 daiToAdd = div(daiUsed, divisor);
        uint256 DaiToChai = sub(daiUsed, daiToAdd);
        // borrow yDai
        require(dai.transferFrom(from, address(this), daiUsed), "addLiquidity: Transfer Failed");
        chai.join(address(this), DaiToChai);
        uint256 balance = chai.balanceOf(address(this));
        controller.post("CHAI", address(this), msg.sender, balance);
        controller.borrow("CHAI", yDai.maturity(), address(this), address(this), DaiToChai);
        dai.approve(address(pool), daiToAdd);
        return pool.mint(daiToAdd);
    }

}