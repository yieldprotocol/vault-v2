// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./YieldMath.sol";
import "../helpers/Delegable.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IYDai.sol";
import "../interfaces/IPool.sol";



/// @dev The Pool contract exchanges Dai for yDai at a price defined by a specific formula.
contract Pool is IPool, ERC20, Delegable {

    event Trade(uint256 maturity, address indexed from, address indexed to, int256 daiTokens, int256 yDaiTokens);
    event Liquidity(uint256 maturity, address indexed from, address indexed to, int256 daiTokens, int256 yDaiTokens, int256 poolTokens);

    int128 constant public k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant public g = int128(uint256((999 << 64)) / 1000); // All constants are `ufixed`, to divide them they must be converted to uint256
    uint128 immutable public maturity;

    IERC20 public override dai;
    IYDai public override yDai;

    constructor(address dai_, address yDai_, string memory name_, string memory symbol_)
        public
        ERC20(name_, symbol_)
        Delegable()
    {
        dai = IERC20(dai_);
        yDai = IYDai(yDai_);

        maturity = toUint128(yDai.maturity());
    }

    /// @dev Trading can only be done before maturity
    modifier beforeMaturity() {
        require(
            now < maturity,
            "Pool: Too late"
        );
        _;
    }

    /// @dev Overflow-protected addition, from OpenZeppelin
    function add(uint128 a, uint128 b)
        internal pure returns (uint128)
    {
        uint128 c = a + b;
        require(c >= a, "Pool: Dai reserves too high");

        return c;
    }

    /// @dev Overflow-protected substraction, from OpenZeppelin
    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        require(b <= a, "Pool: yDai reserves too low");
        uint128 c = a - b;

        return c;
    }

    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= type(uint128).max,
            "Pool: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Safe casting from uint256 to int256
    function toInt256(uint256 x) internal pure returns(int256) {
        require(
            x <= uint256(type(int256).max),
            "Pool: Cast overflow"
        );
        return int256(x);
    }

    /// @dev Mint initial liquidity tokens.
    /// The liquidity provider needs to have called `dai.approve`
    /// @param daiIn The initial Dai liquidity to provide.
    function init(uint128 daiIn)
        external
        beforeMaturity
    {
        require(
            totalSupply() == 0,
            "Pool: Already initialized"
        );
        // no yDai transferred, because initial yDai deposit is entirely virtual
        dai.transferFrom(msg.sender, address(this), daiIn);
        _mint(msg.sender, daiIn);
        emit Liquidity(maturity, msg.sender, msg.sender, -toInt256(daiIn), 0, toInt256(daiIn));
    }

    /// @dev Mint liquidity tokens in exchange for adding dai and yDai
    /// The liquidity provider needs to have called `dai.approve` and `yDai.approve`.
    /// @param daiOffered Amount of `dai` being invested, an appropriate amount of `yDai` to be invested alongside will be calculated and taken by this function from the caller.
    /// @return The amount of liquidity tokens minted.
    function mint(uint256 daiOffered)
        external
        returns (uint256)
    {
        uint256 supply = totalSupply();
        uint256 daiReserves = dai.balanceOf(address(this));
        // use the actual reserves rather than the virtual reserves
        uint256 yDaiReserves = yDai.balanceOf(address(this));
        uint256 tokensMinted = supply.mul(daiOffered).div(daiReserves);
        uint256 yDaiRequired = yDaiReserves.mul(tokensMinted).div(supply);

        require(dai.transferFrom(msg.sender, address(this), daiOffered));
        require(yDai.transferFrom(msg.sender, address(this), yDaiRequired));
        _mint(msg.sender, tokensMinted);
        emit Liquidity(maturity, msg.sender, msg.sender, -toInt256(daiOffered), -toInt256(yDaiRequired), toInt256(tokensMinted));

        return tokensMinted;
    }

    /// @dev Burn liquidity tokens in exchange for dai and yDai.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param tokensBurned Amount of liquidity tokens being burned.
    /// @return The amount of reserve tokens returned (daiTokens, yDaiTokens).
    function burn(uint256 tokensBurned)
        external
        returns (uint256, uint256)
    {
        uint256 supply = totalSupply();
        uint256 daiReserves = dai.balanceOf(address(this));
        // use the actual reserves rather than the virtual reserves
        uint256 yDaiReserves = yDai.balanceOf(address(this));
        uint256 daiReturned = tokensBurned.mul(daiReserves).div(supply);
        uint256 yDaiReturned = tokensBurned.mul(yDaiReserves).div(supply);

        _burn(msg.sender, tokensBurned);
        dai.transfer(msg.sender, daiReturned);
        yDai.transfer(msg.sender, yDaiReturned);
        emit Liquidity(maturity, msg.sender, msg.sender, toInt256(daiReturned), toInt256(yDaiReturned), -toInt256(tokensBurned));

        return (daiReturned, yDaiReturned);
    }

    /// @dev Sell Dai for yDai
    /// The trader needs to have called `dai.approve`
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param daiIn Amount of dai being sold that will be taken from the user's wallet
    /// @return Amount of yDai that will be deposited on `to` wallet
    function sellDai(address from, address to, uint128 daiIn)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 yDaiOut = sellDaiPreview(daiIn);

        dai.transferFrom(from, address(this), daiIn);
        yDai.transfer(to, yDaiOut);
        emit Trade(maturity, from, to, -toInt256(daiIn), toInt256(yDaiOut));

        return yDaiOut;
    }

    /// @dev Returns how much yDai would be obtained by selling `daiIn` dai
    /// @param daiIn Amount of dai hypothetically sold.
    /// @return Amount of yDai hypothetically bought.
    function sellDaiPreview(uint128 daiIn)
        public view override
        beforeMaturity
        returns(uint128)
    {
        uint128 daiReserves = getDaiReserves();
        uint128 yDaiReserves = getYDaiReserves();

        uint128 yDaiOut = YieldMath.yDaiOutForDaiIn(
            daiReserves,
            yDaiReserves,
            daiIn,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g
        );

        require(
            sub(yDaiReserves, yDaiOut) >= add(daiReserves, daiIn),
            "Pool: yDai reserves too low"
        );

        return yDaiOut;
    }

    /// @dev Buy Dai for yDai
    /// The trader needs to have called `yDai.approve`
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought that will be deposited in `to` wallet
    /// @return Amount of yDai that will be taken from `from` wallet
    function buyDai(address from, address to, uint128 daiOut)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 yDaiIn = buyDaiPreview(daiOut);

        yDai.transferFrom(from, address(this), yDaiIn);
        dai.transfer(to, daiOut);
        emit Trade(maturity, from, to, toInt256(daiOut), -toInt256(yDaiIn));

        return yDaiIn;
    }

    /// @dev Returns how much yDai would be required to buy `daiOut` dai.
    /// @param daiOut Amount of dai hypothetically desired.
    /// @return Amount of yDai hypothetically required.
    function buyDaiPreview(uint128 daiOut)
        public view override
        beforeMaturity
        returns(uint128)
    {
        return YieldMath.yDaiInForDaiOut(
            getDaiReserves(),
            getYDaiReserves(),
            daiOut,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g
        );
    }

    /// @dev Sell yDai for Dai
    /// The trader needs to have called `yDai.approve`
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param yDaiIn Amount of yDai being sold that will be taken from the user's wallet
    /// @return Amount of dai that will be deposited on `to` wallet
    function sellYDai(address from, address to, uint128 yDaiIn)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 daiOut = sellYDaiPreview(yDaiIn);

        yDai.transferFrom(from, address(this), yDaiIn);
        dai.transfer(to, daiOut);
        emit Trade(maturity, from, to, toInt256(daiOut), -toInt256(yDaiIn));

        return daiOut;
    }

    /// @dev Returns how much dai would be obtained by selling `yDaiIn` yDai.
    /// @param yDaiIn Amount of yDai hypothetically sold.
    /// @return Amount of Dai hypothetically bought.
    function sellYDaiPreview(uint128 yDaiIn)
        public view override
        beforeMaturity
        returns(uint128)
    {
        return YieldMath.daiOutForYDaiIn(
            getDaiReserves(),
            getYDaiReserves(),
            yDaiIn,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g
        );
    }

    /// @dev Buy yDai for dai
    /// The trader needs to have called `dai.approve`
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param yDaiOut Amount of yDai being bought that will be deposited in `to` wallet
    /// @return Amount of dai that will be taken from `from` wallet
    function buyYDai(address from, address to, uint128 yDaiOut)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 daiIn = buyYDaiPreview(yDaiOut);

        dai.transferFrom(from, address(this), daiIn);
        yDai.transfer(to, yDaiOut);
        emit Trade(maturity, from, to, -toInt256(daiIn), toInt256(yDaiOut));

        return daiIn;
    }


    /// @dev Returns how much dai would be required to buy `yDaiOut` yDai.
    /// @param yDaiOut Amount of yDai hypothetically desired.
    /// @return Amount of Dai hypothetically required.
    function buyYDaiPreview(uint128 yDaiOut)
        public view override
        beforeMaturity
        returns(uint128)
    {
        uint128 daiReserves = getDaiReserves();
        uint128 yDaiReserves = getYDaiReserves();

        uint128 daiIn = YieldMath.daiInForYDaiOut(
            daiReserves,
            yDaiReserves,
            yDaiOut,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g
        );

        require(
            sub(yDaiReserves, yDaiOut) >= add(daiReserves, daiIn),
            "Pool: yDai reserves too low"
        );

        return daiIn;
    }

    /// @dev Returns the "virtual" yDai reserves
    function getYDaiReserves()
        public view
        returns(uint128)
    {
        return toUint128(yDai.balanceOf(address(this)) + totalSupply());
    }

    /// @dev Returns the Dai reserves
    function getDaiReserves()
        public view
        returns(uint128)
    {
        return toUint128(dai.balanceOf(address(this)));
    }
}
