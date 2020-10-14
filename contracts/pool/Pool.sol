// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./YieldMath.sol";
import "../helpers/Delegable.sol";
import "../helpers/ERC20Permit.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IFYDai.sol";
import "../interfaces/IPool.sol";


/// @dev The Pool contract exchanges Dai for fyDai at a price defined by a specific formula.
contract Pool is IPool, Delegable(), ERC20Permit {

    event Trade(uint256 maturity, address indexed from, address indexed to, int256 daiTokens, int256 fyDaiTokens);
    event Liquidity(uint256 maturity, address indexed from, address indexed to, int256 daiTokens, int256 fyDaiTokens, int256 poolTokens);

    int128 constant public k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant public g1 = int128(uint256((950 << 64)) / 1000); // To be used when selling Dai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    int128 constant public g2 = int128(uint256((1000 << 64)) / 950); // To be used when selling fyDai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    uint128 immutable public maturity;

    IERC20 public override dai;
    IFYDai public override fyDai;

    constructor(address dai_, address fyDai_, string memory name_, string memory symbol_)
        public
        ERC20Permit(name_, symbol_)
    {
        dai = IERC20(dai_);
        fyDai = IFYDai(fyDai_);

        maturity = toUint128(fyDai.maturity());
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
        require(b <= a, "Pool: fyDai reserves too low");
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
    function init(uint256 daiIn)
        internal
        beforeMaturity
        returns (uint256)
    {
        require(
            totalSupply() == 0,
            "Pool: Already initialized"
        );
        // no fyDai transferred, because initial fyDai deposit is entirely virtual
        dai.transferFrom(msg.sender, address(this), daiIn);
        _mint(msg.sender, daiIn);
        emit Liquidity(maturity, msg.sender, msg.sender, -toInt256(daiIn), 0, toInt256(daiIn));

        return daiIn;
    }

    /// @dev Mint liquidity tokens in exchange for adding dai and fyDai
    /// The liquidity provider needs to have called `dai.approve` and `fyDai.approve`.
    /// @param from Wallet providing the dai and fyDai. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param daiOffered Amount of `dai` being invested, an appropriate amount of `fyDai` to be invested alongside will be calculated and taken by this function from the caller.
    /// @return The amount of liquidity tokens minted.
    function mint(address from, address to, uint256 daiOffered)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns (uint256)
    {
        uint256 supply = totalSupply();
        if (supply == 0) return init(daiOffered);

        uint256 daiReserves = dai.balanceOf(address(this));
        // use the actual reserves rather than the virtual reserves
        uint256 fyDaiReserves = fyDai.balanceOf(address(this));
        uint256 tokensMinted = supply.mul(daiOffered).div(daiReserves);
        uint256 fyDaiRequired = fyDaiReserves.mul(tokensMinted).div(supply);

        require(daiReserves.add(daiOffered) <= type(uint128).max); // fyDaiReserves can't go over type(uint128).max
        require(supply.add(fyDaiReserves.add(fyDaiRequired)) <= type(uint128).max); // fyDaiReserves can't go over type(uint128).max

        require(dai.transferFrom(from, address(this), daiOffered));
        require(fyDai.transferFrom(from, address(this), fyDaiRequired));
        _mint(to, tokensMinted);
        emit Liquidity(maturity, from, to, -toInt256(daiOffered), -toInt256(fyDaiRequired), toInt256(tokensMinted));

        return tokensMinted;
    }

    /// @dev Burn liquidity tokens in exchange for dai and fyDai.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param from Wallet providing the liquidity tokens. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai and fyDai.
    /// @param tokensBurned Amount of liquidity tokens being burned.
    /// @return The amount of reserve tokens returned (daiTokens, fyDaiTokens).
    function burn(address from, address to, uint256 tokensBurned)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns (uint256, uint256)
    {
        uint256 supply = totalSupply();
        uint256 daiReserves = dai.balanceOf(address(this));
        // use the actual reserves rather than the virtual reserves
        uint256 daiReturned;
        uint256 fyDaiReturned;
        { // avoiding stack too deep
            uint256 fyDaiReserves = fyDai.balanceOf(address(this));
            daiReturned = tokensBurned.mul(daiReserves).div(supply);
            fyDaiReturned = tokensBurned.mul(fyDaiReserves).div(supply);
        }

        _burn(from, tokensBurned);
        dai.transfer(to, daiReturned);
        fyDai.transfer(to, fyDaiReturned);
        emit Liquidity(maturity, from, to, toInt256(daiReturned), toInt256(fyDaiReturned), -toInt256(tokensBurned));

        return (daiReturned, fyDaiReturned);
    }

    /// @dev Sell Dai for fyDai
    /// The trader needs to have called `dai.approve`
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the fyDai being bought
    /// @param daiIn Amount of dai being sold that will be taken from the user's wallet
    /// @return Amount of fyDai that will be deposited on `to` wallet
    function sellDai(address from, address to, uint128 daiIn)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 fyDaiOut = sellDaiPreview(daiIn);

        dai.transferFrom(from, address(this), daiIn);
        fyDai.transfer(to, fyDaiOut);
        emit Trade(maturity, from, to, -toInt256(daiIn), toInt256(fyDaiOut));

        return fyDaiOut;
    }

    /// @dev Returns how much fyDai would be obtained by selling `daiIn` dai
    /// @param daiIn Amount of dai hypothetically sold.
    /// @return Amount of fyDai hypothetically bought.
    function sellDaiPreview(uint128 daiIn)
        public view override
        beforeMaturity
        returns(uint128)
    {
        uint128 daiReserves = getDaiReserves();
        uint128 fyDaiReserves = getFYDaiReserves();

        uint128 fyDaiOut = YieldMath.fyDaiOutForDaiIn(
            daiReserves,
            fyDaiReserves,
            daiIn,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g1
        );

        require(
            sub(fyDaiReserves, fyDaiOut) >= add(daiReserves, daiIn),
            "Pool: fyDai reserves too low"
        );

        return fyDaiOut;
    }

    /// @dev Buy Dai for fyDai
    /// The trader needs to have called `fyDai.approve`
    /// @param from Wallet providing the fyDai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought that will be deposited in `to` wallet
    /// @return Amount of fyDai that will be taken from `from` wallet
    function buyDai(address from, address to, uint128 daiOut)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 fyDaiIn = buyDaiPreview(daiOut);

        fyDai.transferFrom(from, address(this), fyDaiIn);
        dai.transfer(to, daiOut);
        emit Trade(maturity, from, to, toInt256(daiOut), -toInt256(fyDaiIn));

        return fyDaiIn;
    }

    /// @dev Returns how much fyDai would be required to buy `daiOut` dai.
    /// @param daiOut Amount of dai hypothetically desired.
    /// @return Amount of fyDai hypothetically required.
    function buyDaiPreview(uint128 daiOut)
        public view override
        beforeMaturity
        returns(uint128)
    {
        return YieldMath.fyDaiInForDaiOut(
            getDaiReserves(),
            getFYDaiReserves(),
            daiOut,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g2
        );
    }

    /// @dev Sell fyDai for Dai
    /// The trader needs to have called `fyDai.approve`
    /// @param from Wallet providing the fyDai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param fyDaiIn Amount of fyDai being sold that will be taken from the user's wallet
    /// @return Amount of dai that will be deposited on `to` wallet
    function sellFYDai(address from, address to, uint128 fyDaiIn)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 daiOut = sellFYDaiPreview(fyDaiIn);

        fyDai.transferFrom(from, address(this), fyDaiIn);
        dai.transfer(to, daiOut);
        emit Trade(maturity, from, to, toInt256(daiOut), -toInt256(fyDaiIn));

        return daiOut;
    }

    /// @dev Returns how much dai would be obtained by selling `fyDaiIn` fyDai.
    /// @param fyDaiIn Amount of fyDai hypothetically sold.
    /// @return Amount of Dai hypothetically bought.
    function sellFYDaiPreview(uint128 fyDaiIn)
        public view override
        beforeMaturity
        returns(uint128)
    {
        return YieldMath.daiOutForFYDaiIn(
            getDaiReserves(),
            getFYDaiReserves(),
            fyDaiIn,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g2
        );
    }

    /// @dev Buy fyDai for dai
    /// The trader needs to have called `dai.approve`
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the fyDai being bought
    /// @param fyDaiOut Amount of fyDai being bought that will be deposited in `to` wallet
    /// @return Amount of dai that will be taken from `from` wallet
    function buyFYDai(address from, address to, uint128 fyDaiOut)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 daiIn = buyFYDaiPreview(fyDaiOut);

        dai.transferFrom(from, address(this), daiIn);
        fyDai.transfer(to, fyDaiOut);
        emit Trade(maturity, from, to, -toInt256(daiIn), toInt256(fyDaiOut));

        return daiIn;
    }


    /// @dev Returns how much dai would be required to buy `fyDaiOut` fyDai.
    /// @param fyDaiOut Amount of fyDai hypothetically desired.
    /// @return Amount of Dai hypothetically required.
    function buyFYDaiPreview(uint128 fyDaiOut)
        public view override
        beforeMaturity
        returns(uint128)
    {
        uint128 daiReserves = getDaiReserves();
        uint128 fyDaiReserves = getFYDaiReserves();

        uint128 daiIn = YieldMath.daiInForFYDaiOut(
            daiReserves,
            fyDaiReserves,
            fyDaiOut,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g1
        );

        require(
            sub(fyDaiReserves, fyDaiOut) >= add(daiReserves, daiIn),
            "Pool: fyDai reserves too low"
        );

        return daiIn;
    }

    /// @dev Returns the "virtual" fyDai reserves
    function getFYDaiReserves()
        public view override
        returns(uint128)
    {
        return toUint128(fyDai.balanceOf(address(this)).add(totalSupply()));
    }

    /// @dev Returns the Dai reserves
    function getDaiReserves()
        public view override
        returns(uint128)
    {
        return toUint128(dai.balanceOf(address(this)));
    }
}
