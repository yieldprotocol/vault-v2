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

    bytes32 public constant CHAI = "CHAI";

    IERC20 public dai;
    IChai public chai;
    IController public controller;
    IYDai public yDai;
    IPool public pool;

    uint256 public immutable maturity;

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
        maturity = yDai.maturity();
        require(
            controller.containsSeries(yDai.maturity()),
            "LiquidityProxy: Mismatched Pool and Controller"
        );

        dai.approve(address(chai), uint256(-1));
        dai.approve(address(pool), uint256(-1));
        yDai.approve(address(pool), uint256(-1));
        chai.approve(treasury_, uint256(-1));
    }

    /// @dev Mints liquidity with provided Dai by borrowing yDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(liquidityProxy)` and `pool.addDelegate(liquidityProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxYDai maximum amount of yDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(uint256 daiUsed, uint256 maxYDai) external returns (uint256)
    {
        require(yDai.isMature() != true, "LiquidityProxy: Only before maturity");
        require(dai.transferFrom(msg.sender, address(this), daiUsed), "LiquidityProxy: Transfer Failed");
        
        // calculate needed yDai
        uint256 daiReserves = pool.getDaiReserves();
        uint256 yDaiReserves = pool.getYDaiReserves();
        uint256 daiToConvert = daiUsed.mul(daiReserves).div(yDaiReserves.add(daiReserves));
        require(
            daiToConvert <= maxYDai,
            "LiquidityProxy: maxYDai exceeded"
        ); // 1 Dai == 1 yDai

        // convert dai to chai and borrow needed yDai
        chai.join(address(this), daiToConvert);
        // look at the balance of chai in dai to avoid rounding issues
        uint256 toBorrow = chai.dai(address(this));
        controller.post(CHAI, address(this), msg.sender, chai.balanceOf(address(this)));
        controller.borrow(CHAI, maturity, msg.sender, address(this), toBorrow);
        
        // mint liquidity tokens
        uint256 daiToAdd = daiUsed.sub(daiToConvert);
        return pool.mint(address(this), msg.sender, daiToAdd);
    }

    /// @dev Burns tokens and repays yDai debt. Buys needed yDai or sells any excess, and all Dai is returned.
    /// Caller must have approved the proxy using`controller.addDelegate(liquidityProxy)` and `pool.addDelegate(liquidityProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumDai minimum amount of Dai to be bought with yDai when burning. 
    function removeLiquidityEarly(uint256 poolTokens, uint256 minimumDai) external
    {
        (, uint256 yDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);

        controller.repayYDai(CHAI, maturity, address(this), msg.sender, yDaiObtained);
        uint256 remainingYDai = yDai.balanceOf(address(this));
        if (remainingYDai > 0) {
            require(
                pool.sellYDai(address(this), address(this), uint128(remainingYDai)) >= minimumDai,
                "LiquidityProxy: minimumDai not reached"
            );
        }
        if (controller.debtYDai(CHAI, maturity, msg.sender) == 0) withdrawDai();
    }

    /// @dev Burns tokens and repays yDai debt after Maturity. 
    /// Caller must have approved the proxy using`controller.addDelegate(liquidityProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    function removeLiquidityMature(uint256 poolTokens) external
    {
        (, uint256 yDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);
        if (yDaiObtained > 0) yDai.redeem(address(this), address(this), yDaiObtained);
        controller.repayDai(CHAI, maturity, address(this), msg.sender, dai.balanceOf(address(this)));
        if (controller.debtYDai(CHAI, maturity, msg.sender) == 0) withdrawDai();
    }

    /// @dev Return to caller all posted chai, converted to dai.
    function withdrawDai() internal {
        controller.withdraw(CHAI, msg.sender, address(this), controller.posted(CHAI, msg.sender));
        chai.exit(address(this), chai.balanceOf(address(this)));
        require(dai.transfer(msg.sender, dai.balanceOf(address(this))), "LiquidityProxy: Dai Transfer Failed");
    }
}