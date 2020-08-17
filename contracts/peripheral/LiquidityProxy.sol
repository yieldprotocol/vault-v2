// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IController.sol";
import "../interfaces/IChai.sol";
import "../interfaces/IPool.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@nomiclabs/buidler/console.sol";

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
    //function div(uint x, uint y) internal pure returns (uint z) {
    //    z = mul(x, ONE) / y;
    //}

    // @dev mints liquidity with provided Dai by borrowing yDai with some of the Dai
    /// @param from Wallet providing the dai being used. Must have approved the operator with `dai.approve(operator)` and `controller..addDelegate(operator)`.
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxYDai maximum amount of yDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(address from,  uint256 daiUsed, uint256 maxYDai) external returns (uint256)
    {
        require(dai.transferFrom(from, address(this), daiUsed), "addLiquidity: Transfer Failed");
        
        // calculate needed yDai
        uint256 daiReserves = dai.balanceOf(address(pool));
        uint256 yDaiReserves = yDai.balanceOf(address(pool));
        uint256 daiToChai = mul(daiUsed, yDaiReserves) / add(yDaiReserves, daiReserves);
        require(daiToChai <= maxYDai, "LiquidityProxy: maxYDai exceeded");
        uint256 daiToAdd = sub(daiUsed, daiToChai);

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
    /// @param from Wallet providing the dai being burned. Must have approved the operator with `pool.approve(operator)` and `controller.addDelegate(operator)`.
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param daiLimit maximum amount of Dai to be bought or sold with yDai when burning. 
    function removeLiquidityEarly(address from, uint256 poolTokens, uint256 daiLimit) external returns (uint256)
    {
        (, uint256 yDaiObtained) = pool.burn(from, address(this), poolTokens);

        controller.repayYDai("CHAI", yDai.maturity(), address(this), from, yDaiObtained);
        uint256 remainingYDai = yDai.balanceOf(address(this));
        if (remainingYDai > 0) {
            pool.sellYDai(address(this), address(this), uint128(remainingYDai));
        }

        // Doing this is quite dangerous, I would do it only if there is no debt left
        // controller.withdraw("CHAI", from, address(this), controller.posted("CHAI", from));
        // unwrap Chai
        // chai.exit(address(this), chai.balanceOf(address(this)));
        require(dai.transfer(from, dai.balanceOf(address(this))), "removeLiquidityEarlySell: Dai Transfer Failed");
        
    }

    /// @dev burns tokens and repays yDai debt after Maturity. 
    /// @param from Wallet providing the dai being burned. Must have approved the operator with `pool.approve(operator)` and `controller.addDelegate(operator)`.
    /// @param poolTokens amount of pool tokens to burn. 
    function removeLiquidityMature(address from, uint256 poolTokens) external returns (uint256)
    {
        (, uint256 yDaiObtained) = pool.burn(from, address(this), poolTokens);
        if (yDaiObtained > 0){
            yDai.redeem(address(this), address(this), yDaiObtained);
        }

        controller.repayDai("CHAI", yDai.maturity(), address(this), from, dai.balanceOf(address(this)));
        // Doing this is quite dangerous, I would do it only if there is no debt left
        // controller.withdraw("CHAI", from, from, controller.posted("CHAI", from));
        // unwrap Chai
        // chai.exit(address(this), chai.balanceOf(address(this)));
        require(dai.transfer(from, dai.balanceOf(address(this))), "removeLiquidityMature: Dai Transfer Failed");
        
    }
}