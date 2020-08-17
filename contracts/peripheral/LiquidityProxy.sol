// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IController.sol";
import "../interfaces/IChai.sol";
import "../interfaces/IPool.sol";
import "@nomiclabs/buidler/console.sol";

/**
 * @dev The LiquidityProxy is a proxy contract of Pool that allows users to mint liquidity tokens with just Dai. 
 */
contract LiquidityProxy {
    using SafeMath for uint256;

    IERC20 public dai;
    IChai public chai;
    IController public controller;
    IYDai public yDai;
    IPool public pool;

    /// @dev The constructor links ControllerDai to vat, pot, controller and pool.
    constructor (
        address dai_,
        address chai_,
        address treasury_,
        address controller_,
        address pool_
    ) public {
        dai = IERC20(dai_);
        chai = IChai(chai_);
        controller = IController(controller_);
        pool = IPool(pool_);

        yDai = pool.yDai();
        require(
            controller.containsSeries(yDai.maturity()),
            "DaiProxy: Mismatched Pool and Controller"
        );

        dai.approve(address(chai), uint256(-1));
        dai.approve(address(pool), uint256(-1));
        yDai.approve(address(pool), uint256(-1));
        chai.approve(treasury_, uint256(-1));
    }

    /// @dev mints liquidity with provided Dai by borrowing yDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(liquidityProxy)` and `pool.addDelegate(liquidityProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxYDai maximum amount of yDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(uint256 daiUsed, uint256 maxYDai) external returns (uint256)
    {
        require(dai.transferFrom(msg.sender, address(this), daiUsed), "addLiquidity: Transfer Failed");
        
        // calculate needed yDai
        uint256 daiReserves = dai.balanceOf(address(pool));
        uint256 yDaiReserves = yDai.balanceOf(address(pool));
        uint256 daiToChai = daiUsed.mul(yDaiReserves).div(yDaiReserves.add(daiReserves));
        require(daiToChai <= maxYDai, "LiquidityProxy: maxYDai exceeded");
        uint256 daiToAdd = daiUsed.sub(daiToChai);

        // borrow needed yDai
        chai.join(address(this), daiToChai);
        uint256 balance = chai.balanceOf(address(this));
        // look at the balance of chai in dai to avoid rounding issues
        uint256 toBorrow = chai.dai(address(this));
        controller.post("CHAI", address(this), msg.sender, balance);
        controller.borrow("CHAI", yDai.maturity(), msg.sender, address(this), toBorrow);
        
        // mint liquidity tokens
        return pool.mint(address(this), msg.sender, daiToAdd);
    }

    /// @dev burns tokens and repays yDai debt. Buys needed yDai or sells any excess, and all Dai is returned.
    /// Caller must have approved the proxy using`controller.addDelegate(liquidityProxy)` and `pool.addDelegate(liquidityProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param daiLimit maximum amount of Dai to be bought or sold with yDai when burning. 
    function removeLiquidityEarly(uint256 poolTokens, uint256 daiLimit) external returns (uint256)
    {
        (, uint256 yDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);

        controller.repayYDai("CHAI", yDai.maturity(), address(this), msg.sender, yDaiObtained);
        uint256 remainingYDai = yDai.balanceOf(address(this));
        if (remainingYDai > 0) {
            pool.sellYDai(address(this), address(this), uint128(remainingYDai));
        }

        // Doing this is quite dangerous, I would do it only if there is no debt left
        // controller.withdraw("CHAI", msg.sender, address(this), controller.posted("CHAI", msg.sender));
        // unwrap Chai
        // chai.exit(address(this), chai.balanceOf(address(this)));
        require(dai.transfer(msg.sender, dai.balanceOf(address(this))), "removeLiquidityEarlySell: Dai Transfer Failed");
        
    }

    /// @dev burns tokens and repays yDai debt after Maturity. 
    /// Caller must have approved the proxy using`controller.addDelegate(liquidityProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    function removeLiquidityMature(uint256 poolTokens) external returns (uint256)
    {
        (, uint256 yDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);
        if (yDaiObtained > 0){
            yDai.redeem(address(this), address(this), yDaiObtained);
        }

        controller.repayDai("CHAI", yDai.maturity(), address(this), msg.sender, dai.balanceOf(address(this)));
        // Doing this is quite dangerous, I would do it only if there is no debt left
        // controller.withdraw("CHAI", msg.sender, address(this), controller.posted("CHAI", msg.sender));
        // unwrap Chai
        // chai.exit(address(this), chai.balanceOf(address(this)));
        require(dai.transfer(msg.sender, dai.balanceOf(address(this))), "removeLiquidityMature: Dai Transfer Failed");
    }
}