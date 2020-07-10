pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Market.sol";
import "../helpers/Delegable.sol";
import "../interfaces/IMarket.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Market contract exchanges Dai for yDai at a price defined by a specific formula.
contract LimitMarket is Delegable {
    using SafeMath for uint256;

    IERC20 public chai;
    IERC20 public yDai;
    IMarket public market;

    constructor(address chai_, address yDai_, address market_) public Delegable() {
        chai = IERC20(chai_);
        yDai = IERC20(yDai_);
        market = IMarket(market_);
    }

/*    /// @dev Mint liquidity tokens in exchange for adding chai and yDai
    /// The parameter passed is the amount of `chai` being invested, an appropriate amount of `yDai` to be invested alongside will be calculated and taken by this function from the caller.
    function mint(uint256 chaiOffered) external {
        uint256 supply = totalSupply();
        uint256 chaiReserves = chai.balanceOf(address(this));
        uint256 yDaiReserves = yDai.balanceOf(address(this));
        uint256 tokensMinted = supply.mul(chaiOffered).div(chaiReserves);
        uint256 yDaiRequired = yDaiReserves.mul(tokensMinted).div(supply);

        chai.transferFrom(msg.sender, address(this), chaiOffered);
        yDai.transferFrom(msg.sender, address(this), yDaiRequired);
        _mint(msg.sender, tokensMinted);

        _updateState(chaiReserves.add(chaiOffered), yDaiReserves.add(yDaiRequired));
    }

    /// @dev Burn liquidity tokens in exchange for chai and yDai
    function burn(uint256 tokensBurned) external {
        uint256 supply = totalSupply();
        uint256 chaiReserves = chai.balanceOf(address(this));
        uint256 yDaiReserves = yDai.balanceOf(address(this));
        uint256 chaiReturned = tokensBurned.mul(chaiReserves).div(supply);
        uint256 yDaiReturned = tokensBurned.mul(yDaiReserves).div(supply);

        _burn(msg.sender, tokensBurned);
        chai.transfer(msg.sender, chaiReturned);
        yDai.transfer(msg.sender, yDaiReturned);

        _updateState(chaiReserves.sub(chaiReturned), yDaiReserves.sub(yDaiReturned));
    } */

    /// @dev Sell Chai for yDai
    /// @param from Wallet providing the chai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param chaiIn Amount of chai being sold that will be taken from the user's wallet
    /// @param minYDaiOut Amount of yDai being received that will be accepted as a minimum for the trade to execute
    function sellChai(address from, address to, uint128 chaiIn, uint128 minYDaiOut)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
    {
        uint256 previousBalance = yDai.balanceOf(to);
        market.sellChai(from, to, chaiIn);
        require(
            yDai.balanceOf(to) >= previousBalance.add(minYDaiOut),
            "LimitMarket: Limit not reached"
        );
    }

    /// @dev Buy Chai for yDai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the chai being bought
    /// @param chaiOut Amount of chai being bought that will be deposited in `to` wallet
    /// @param maxYDaiIn Amount of yDai being paid that will be accepted as a maximum for the trade to execute
    function buyChai(address from, address to, uint128 chaiOut, uint128 maxYDaiIn)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
    {
        uint256 previousBalance = yDai.balanceOf(from);
        market.buyChai(from, to, chaiOut);
        require(
            yDai.balanceOf(from) >= previousBalance.sub(maxYDaiIn),
            "LimitMarket: Limit exceeded"
        );
    }

    /// @dev Sell yDai for Chai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the chai being bought
    /// @param yDaiIn Amount of yDai being sold that will be taken from the user's wallet
    /// @param minChaiOut Amount of chai being received that will be accepted as a minimum for the trade to execute
    function sellYDai(address from, address to, uint128 yDaiIn, uint128 minChaiOut)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
    {
        uint256 previousBalance = chai.balanceOf(to);
        market.sellYDai(from, to, yDaiIn);
        require(
            chai.balanceOf(to) >= previousBalance.add(minChaiOut),
            "LimitMarket: Limit not reached"
        );
    }

    /// @dev Buy yDai for chai
    /// @param from Wallet providing the chai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param yDaiOut Amount of yDai being bought that will be deposited in `to` wallet
    /// @param maxChaiIn Amount of chai being paid that will be accepted as a maximum for the trade to execute
    function buyYDai(address from, address to, uint128 yDaiOut, uint128 maxChaiIn)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
    {
        uint256 previousBalance = chai.balanceOf(from);
        market.buyYDai(from, to, yDaiOut);
        require(
            chai.balanceOf(from) >= previousBalance.sub(maxChaiIn),
            "LimitMarket: Limit exceeded"
        );
    }
}