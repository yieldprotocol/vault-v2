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

    /// @dev Sell Chai for yDai
    /// @param from Wallet providing the chai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param chaiIn Amount of chai being sold that will be taken from the user's wallet
    /// @param minYDaiOut Amount of yDai being received that will be accepted as a minimum for the trade to execute
    function sellChai(address from, address to, uint128 chaiIn, uint128 minYDaiOut)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
        returns(uint256)
    {
        uint256 yDaiOut = market.sellChai(from, to, chaiIn);
        require(
            yDaiOut >= minYDaiOut,
            "LimitMarket: Limit not reached"
        );
        return yDaiOut;
    }

    /// @dev Buy Chai for yDai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the chai being bought
    /// @param chaiOut Amount of chai being bought that will be deposited in `to` wallet
    /// @param maxYDaiIn Amount of yDai being paid that will be accepted as a maximum for the trade to execute
    function buyChai(address from, address to, uint128 chaiOut, uint128 maxYDaiIn)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
        returns(uint256)
    {
        uint256 yDaiIn = market.buyChai(from, to, chaiOut);
        require(
            maxYDaiIn >= yDaiIn,
            "LimitMarket: Limit exceeded"
        );
        return yDaiIn;
    }

    /// @dev Sell yDai for Chai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the chai being bought
    /// @param yDaiIn Amount of yDai being sold that will be taken from the user's wallet
    /// @param minChaiOut Amount of chai being received that will be accepted as a minimum for the trade to execute
    function sellYDai(address from, address to, uint128 yDaiIn, uint128 minChaiOut)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
        returns(uint256)
    {
        uint256 chaiOut = market.sellYDai(from, to, yDaiIn);
        require(
            chaiOut >= minChaiOut,
            "LimitMarket: Limit not reached"
        );
        return chaiOut;
    }

    /// @dev Buy yDai for chai
    /// @param from Wallet providing the chai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param yDaiOut Amount of yDai being bought that will be deposited in `to` wallet
    /// @param maxChaiIn Amount of chai being paid that will be accepted as a maximum for the trade to execute
    function buyYDai(address from, address to, uint128 yDaiOut, uint128 maxChaiIn)
        external
        onlyHolderOrDelegate(from, "LimitMarket: Only Holder Or Delegate")
        returns(uint256)
    {
        uint256 chaiIn = market.buyYDai(from, to, yDaiOut);
        require(
            maxChaiIn >= chaiIn,
            "LimitMarket: Limit exceeded"
        );
        return chaiIn;
    }
}