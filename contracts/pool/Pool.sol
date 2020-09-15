// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./YieldMath.sol";
import "../helpers/Delegable.sol";
import "../helpers/ERC20Permit.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IEDai.sol";
import "../interfaces/IPool.sol";


/// @dev The Pool contract exchanges Dai for eDai at a price defined by a specific formula.
contract Pool is IPool, Delegable(), ERC20Permit {

    event Trade(uint256 maturity, address indexed from, address indexed to, int256 daiTokens, int256 eDaiTokens);
    event Liquidity(uint256 maturity, address indexed from, address indexed to, int256 daiTokens, int256 eDaiTokens, int256 poolTokens);

    int128 constant public k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant public g1 = int128(uint256((950 << 64)) / 1000); // To be used when selling Dai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    int128 constant public g2 = int128(uint256((1000 << 64)) / 950); // To be used when selling eDai to the pool. All constants are `ufixed`, to divide them they must be converted to uint256
    uint128 immutable public maturity;

    IERC20 public override dai;
    IEDai public override eDai;

    constructor(address dai_, address eDai_, string memory name_, string memory symbol_)
        public
        ERC20Permit(name_, symbol_)
    {
        dai = IERC20(dai_);
        eDai = IEDai(eDai_);

        maturity = toUint128(eDai.maturity());
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
        require(b <= a, "Pool: eDai reserves too low");
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
        // no eDai transferred, because initial eDai deposit is entirely virtual
        dai.transferFrom(msg.sender, address(this), daiIn);
        _mint(msg.sender, daiIn);
        emit Liquidity(maturity, msg.sender, msg.sender, -toInt256(daiIn), 0, toInt256(daiIn));
    }

    /// @dev Mint liquidity tokens in exchange for adding dai and eDai
    /// The liquidity provider needs to have called `dai.approve` and `eDai.approve`.
    /// @param from Wallet providing the dai and eDai. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param daiOffered Amount of `dai` being invested, an appropriate amount of `eDai` to be invested alongside will be calculated and taken by this function from the caller.
    /// @return The amount of liquidity tokens minted.
    function mint(address from, address to, uint256 daiOffered)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns (uint256)
    {
        uint256 supply = totalSupply();
        uint256 daiReserves = dai.balanceOf(address(this));
        // use the actual reserves rather than the virtual reserves
        uint256 eDaiReserves = eDai.balanceOf(address(this));
        uint256 tokensMinted = supply.mul(daiOffered).div(daiReserves);
        uint256 eDaiRequired = eDaiReserves.mul(tokensMinted).div(supply);

        require(dai.transferFrom(from, address(this), daiOffered));
        require(eDai.transferFrom(from, address(this), eDaiRequired));
        _mint(to, tokensMinted);
        emit Liquidity(maturity, from, to, -toInt256(daiOffered), -toInt256(eDaiRequired), toInt256(tokensMinted));

        return tokensMinted;
    }

    /// @dev Burn liquidity tokens in exchange for dai and eDai.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param from Wallet providing the liquidity tokens. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai and eDai.
    /// @param tokensBurned Amount of liquidity tokens being burned.
    /// @return The amount of reserve tokens returned (daiTokens, eDaiTokens).
    function burn(address from, address to, uint256 tokensBurned)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns (uint256, uint256)
    {
        uint256 supply = totalSupply();
        uint256 daiReserves = dai.balanceOf(address(this));
        // use the actual reserves rather than the virtual reserves
        uint256 daiReturned;
        uint256 eDaiReturned;
        { // avoiding stack too deep
            uint256 eDaiReserves = eDai.balanceOf(address(this));
            daiReturned = tokensBurned.mul(daiReserves).div(supply);
            eDaiReturned = tokensBurned.mul(eDaiReserves).div(supply);
        }

        _burn(from, tokensBurned);
        dai.transfer(to, daiReturned);
        eDai.transfer(to, eDaiReturned);
        emit Liquidity(maturity, from, to, toInt256(daiReturned), toInt256(eDaiReturned), -toInt256(tokensBurned));

        return (daiReturned, eDaiReturned);
    }

    /// @dev Sell Dai for eDai
    /// The trader needs to have called `dai.approve`
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the eDai being bought
    /// @param daiIn Amount of dai being sold that will be taken from the user's wallet
    /// @return Amount of eDai that will be deposited on `to` wallet
    function sellDai(address from, address to, uint128 daiIn)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 eDaiOut = sellDaiPreview(daiIn);

        dai.transferFrom(from, address(this), daiIn);
        eDai.transfer(to, eDaiOut);
        emit Trade(maturity, from, to, -toInt256(daiIn), toInt256(eDaiOut));

        return eDaiOut;
    }

    /// @dev Returns how much eDai would be obtained by selling `daiIn` dai
    /// @param daiIn Amount of dai hypothetically sold.
    /// @return Amount of eDai hypothetically bought.
    function sellDaiPreview(uint128 daiIn)
        public view override
        beforeMaturity
        returns(uint128)
    {
        uint128 daiReserves = getDaiReserves();
        uint128 eDaiReserves = getEDaiReserves();

        uint128 eDaiOut = YieldMath.eDaiOutForDaiIn(
            daiReserves,
            eDaiReserves,
            daiIn,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g1
        );

        require(
            sub(eDaiReserves, eDaiOut) >= add(daiReserves, daiIn),
            "Pool: eDai reserves too low"
        );

        return eDaiOut;
    }

    /// @dev Buy Dai for eDai
    /// The trader needs to have called `eDai.approve`
    /// @param from Wallet providing the eDai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought that will be deposited in `to` wallet
    /// @return Amount of eDai that will be taken from `from` wallet
    function buyDai(address from, address to, uint128 daiOut)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 eDaiIn = buyDaiPreview(daiOut);

        eDai.transferFrom(from, address(this), eDaiIn);
        dai.transfer(to, daiOut);
        emit Trade(maturity, from, to, toInt256(daiOut), -toInt256(eDaiIn));

        return eDaiIn;
    }

    /// @dev Returns how much eDai would be required to buy `daiOut` dai.
    /// @param daiOut Amount of dai hypothetically desired.
    /// @return Amount of eDai hypothetically required.
    function buyDaiPreview(uint128 daiOut)
        public view override
        beforeMaturity
        returns(uint128)
    {
        return YieldMath.eDaiInForDaiOut(
            getDaiReserves(),
            getEDaiReserves(),
            daiOut,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g2
        );
    }

    /// @dev Sell eDai for Dai
    /// The trader needs to have called `eDai.approve`
    /// @param from Wallet providing the eDai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param eDaiIn Amount of eDai being sold that will be taken from the user's wallet
    /// @return Amount of dai that will be deposited on `to` wallet
    function sellEDai(address from, address to, uint128 eDaiIn)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 daiOut = sellEDaiPreview(eDaiIn);

        eDai.transferFrom(from, address(this), eDaiIn);
        dai.transfer(to, daiOut);
        emit Trade(maturity, from, to, toInt256(daiOut), -toInt256(eDaiIn));

        return daiOut;
    }

    /// @dev Returns how much dai would be obtained by selling `eDaiIn` eDai.
    /// @param eDaiIn Amount of eDai hypothetically sold.
    /// @return Amount of Dai hypothetically bought.
    function sellEDaiPreview(uint128 eDaiIn)
        public view override
        beforeMaturity
        returns(uint128)
    {
        return YieldMath.daiOutForEDaiIn(
            getDaiReserves(),
            getEDaiReserves(),
            eDaiIn,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g2
        );
    }

    /// @dev Buy eDai for dai
    /// The trader needs to have called `dai.approve`
    /// @param from Wallet providing the dai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the eDai being bought
    /// @param eDaiOut Amount of eDai being bought that will be deposited in `to` wallet
    /// @return Amount of dai that will be taken from `from` wallet
    function buyEDai(address from, address to, uint128 eDaiOut)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128)
    {
        uint128 daiIn = buyEDaiPreview(eDaiOut);

        dai.transferFrom(from, address(this), daiIn);
        eDai.transfer(to, eDaiOut);
        emit Trade(maturity, from, to, -toInt256(daiIn), toInt256(eDaiOut));

        return daiIn;
    }


    /// @dev Returns how much dai would be required to buy `eDaiOut` eDai.
    /// @param eDaiOut Amount of eDai hypothetically desired.
    /// @return Amount of Dai hypothetically required.
    function buyEDaiPreview(uint128 eDaiOut)
        public view override
        beforeMaturity
        returns(uint128)
    {
        uint128 daiReserves = getDaiReserves();
        uint128 eDaiReserves = getEDaiReserves();

        uint128 daiIn = YieldMath.daiInForEDaiOut(
            daiReserves,
            eDaiReserves,
            eDaiOut,
            toUint128(maturity - now), // This can't be called after maturity
            k,
            g1
        );

        require(
            sub(eDaiReserves, eDaiOut) >= add(daiReserves, daiIn),
            "Pool: eDai reserves too low"
        );

        return daiIn;
    }

    /// @dev Returns the "virtual" eDai reserves
    function getEDaiReserves()
        public view override
        returns(uint128)
    {
        return toUint128(eDai.balanceOf(address(this)) + totalSupply());
    }

    /// @dev Returns the Dai reserves
    function getDaiReserves()
        public view override
        returns(uint128)
    {
        return toUint128(dai.balanceOf(address(this)));
    }
}
