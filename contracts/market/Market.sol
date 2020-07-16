// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./YieldMath.sol";
import "../helpers/Delegable.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IYDai.sol";
import "../interfaces/IMarket.sol";
// import "@nomiclabs/buidler/console.sol";


/// @dev The Market contract exchanges Dai for yDai at a price defined by a specific formula.
contract Market is IMarket, ERC20, Delegable {

    int128 constant public k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant public g = int128(uint256((999 << 64)) / 1000); // All constants are `ufixed`, to divide them they must be converted to uint256
    uint256 constant public initialSupply = 1000;
    uint128 immutable public maturity;

    IERC20 public dai;
    IYDai public yDai;

    // TODO: Choose liquidity token name
    constructor(address dai_, address yDai_) public ERC20("Name", "Symbol") Delegable() {
        dai = IERC20(dai_);
        yDai = IYDai(yDai_);

        maturity = toUint128(yDai.maturity());
    }

    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= 340282366920938463463374607431768211455,
            "Market: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev max(0, x - y)
    function subFloorZero(uint256 x, uint256 y) public pure returns(uint256) {
        if (y >= x) return 0;
        else return x - y;
    }

    /// @dev Mint initial liquidity tokens
    function init(uint256 daiIn, uint256 yDaiIn) external {
        require(
            totalSupply() == 0,
            "Market: Already initialized"
        );

        dai.transferFrom(msg.sender, address(this), daiIn);
        yDai.transferFrom(msg.sender, address(this), yDaiIn);
        _mint(msg.sender, initialSupply);
    }

    /// @dev Mint liquidity tokens in exchange for adding dai and yDai
    /// The parameter passed is the amount of `dai` being invested, an appropriate amount of `yDai` to be invested alongside will be calculated and taken by this function from the caller.
    function mint(uint256 daiOffered) external {
        uint256 supply = totalSupply();
        uint256 daiReserves = dai.balanceOf(address(this));
        uint256 yDaiReserves = yDai.balanceOf(address(this));
        uint256 tokensMinted = supply.mul(daiOffered).div(daiReserves);
        uint256 yDaiRequired = yDaiReserves.mul(tokensMinted).div(supply);

        dai.transferFrom(msg.sender, address(this), daiOffered);
        yDai.transferFrom(msg.sender, address(this), yDaiRequired);
        _mint(msg.sender, tokensMinted);
    }

    /// @dev Burn liquidity tokens in exchange for dai and yDai
    function burn(uint256 tokensBurned) external {
        uint256 supply = totalSupply();
        uint256 daiReserves = dai.balanceOf(address(this));
        uint256 yDaiReserves = yDai.balanceOf(address(this));
        uint256 daiReturned = tokensBurned.mul(daiReserves).div(supply);
        uint256 yDaiReturned = tokensBurned.mul(yDaiReserves).div(supply);

        _burn(msg.sender, tokensBurned);
        dai.transfer(msg.sender, daiReturned);
        yDai.transfer(msg.sender, yDaiReturned);
    }

    /// @dev Sell Dai for yDai
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param daiIn Amount of dai being sold that will be taken from the user's wallet
    /// @return Amount of yDai that will be deposited on `to` wallet
    function sellDai(address from, address to, uint128 daiIn)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
        returns(uint256)
    {
        uint128 daiReserves = toUint128(dai.balanceOf(address(this)));
        uint128 yDaiReserves = toUint128(yDai.balanceOf(address(this)));
        uint256 yDaiOut = YieldMath.yDaiOutForDaiIn(
            daiReserves,
            yDaiReserves,
            daiIn,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );

        dai.transferFrom(from, address(this), daiIn);
        yDai.transfer(to, yDaiOut);

        return yDaiOut;
    }

    /// @dev Returns how much yDai would be obtained by selling `daiIn` dai
    function sellDaiPreview(uint128 daiIn) external view returns(uint256) {
        return YieldMath.yDaiOutForDaiIn(
            toUint128(dai.balanceOf(address(this))),
            toUint128(yDai.balanceOf(address(this))),
            daiIn,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );
    }

    /// @dev Buy Dai for yDai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought that will be deposited in `to` wallet
    /// @return Amount of yDai that will be taken from `from` wallet
    function buyDai(address from, address to, uint128 daiOut)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
        returns(uint256)
    {
        uint128 daiReserves = toUint128(dai.balanceOf(address(this)));
        uint128 yDaiReserves = toUint128(yDai.balanceOf(address(this)));
        uint256 yDaiIn = YieldMath.yDaiInForDaiOut(
            daiReserves,
            yDaiReserves,
            daiOut,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );

        yDai.transferFrom(from, address(this), yDaiIn);
        dai.transfer(to, daiOut);

        return yDaiIn;
    }

    /// @dev Returns how much yDai would be required to buy `daiOut` dai
    function buyDaiPreview(uint128 daiOut) external view returns(uint256) {
        return YieldMath.yDaiInForDaiOut(
            toUint128(dai.balanceOf(address(this))),
            toUint128(yDai.balanceOf(address(this))),
            daiOut,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );
    }

    /// @dev Sell yDai for Dai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param yDaiIn Amount of yDai being sold that will be taken from the user's wallet
    /// @return Amount of dai that will be deposited on `to` wallet
    function sellYDai(address from, address to, uint128 yDaiIn)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
        returns(uint256)
    {
        uint128 daiReserves = toUint128(dai.balanceOf(address(this)));
        uint128 yDaiReserves = toUint128(yDai.balanceOf(address(this)));
        uint256 daiOut = YieldMath.daiOutForYDaiIn(
            daiReserves, yDaiReserves,
            yDaiIn,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );

        yDai.transferFrom(from, address(this), yDaiIn);
        dai.transfer(to, daiOut);

        return daiOut;
    }

    /// @dev Returns how much dai would be obtained by selling `yDaiIn` yDai
    function sellYDaiPreview(uint128 yDaiIn) external view returns(uint256) {
        return YieldMath.daiOutForYDaiIn(
            toUint128(dai.balanceOf(address(this))),
            toUint128(yDai.balanceOf(address(this))),
            yDaiIn,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );
    }

    /// @dev Buy yDai for dai
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param yDaiOut Amount of yDai being bought that will be deposited in `to` wallet
    /// @return Amount of dai that will be taken from `from` wallet
    function buyYDai(address from, address to, uint128 yDaiOut)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
        returns(uint256)
    {
        uint128 daiReserves = toUint128(dai.balanceOf(address(this)));
        uint128 yDaiReserves = toUint128(yDai.balanceOf(address(this)));
        uint256 daiIn = YieldMath.daiInForYDaiOut(
            daiReserves, yDaiReserves,
            yDaiOut,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );

        dai.transferFrom(from, address(this), daiIn);
        yDai.transfer(to, yDaiOut);

        return daiIn;
    }


    /// @dev Returns how much dai would be required to buy `yDaiOut` yDai
    function buyYDaiPreview(uint128 yDaiOut) external view returns(uint256) {
        return YieldMath.daiInForYDaiOut(
            toUint128(dai.balanceOf(address(this))),
            toUint128(yDai.balanceOf(address(this))),
            yDaiOut,
            toUint128(subFloorZero(maturity, now)),
            k,
            g
        );
    }
}