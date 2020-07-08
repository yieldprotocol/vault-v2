pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../helpers/Constants.sol";
import "../helpers/Delegable.sol";
import "../helpers/YieldMath.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IYDai.sol";
import "../interfaces/IMarket.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Market contract exchanges Dai for yDai at a price defined by a specific formula.
contract Market is IMarket, ERC20, Delegable, Constants {

    struct State {
        uint32 timestamp;    // last time contract was updated. wraps around after 2^32
        uint32 prevRate;     // UQ16x16 interest rate last time the contract was updated
        uint64 accumulator;  // interest rate oracle accumulator—32 bits for a UQ16x16, 32 bits for overflow
    }

    int128 constant public k = int128(uint256((1 << 64)) / 126144000); // 1 / Seconds in 4 years, in 64.64
    int128 constant public g = int128(uint256((999 << 64)) / 1000); // All constants are `ufixed`, to divide them they must be converted to uint256
    uint256 constant public initialSupply = 1000;
    uint128 immutable public maturity;

    IPot internal _pot;
    IERC20 public chai;
    IYDai public yDai;

    State internal state;

    // TODO: Choose liquidity token name
    constructor(address pot_, address chai_, address yDai_) public ERC20("Name", "Symbol") Delegable() {
        _pot = IPot(pot_);
        chai = IERC20(chai_);
        yDai = IYDai(yDai_);

        maturity = uint128(yDai.maturity()); // SafeCast might be needed if repurposing, but not right now.
    }

    /// @dev Mint initial liquidity tokens
    function init(uint256 chaiIn, uint256 yDaiIn) external {
        require(
            totalSupply() == 0,
            "Market: Already initialized"
        );

        chai.transferFrom(msg.sender, address(this), chaiIn);
        yDai.transferFrom(msg.sender, address(this), yDaiIn);
        _mint(msg.sender, initialSupply);

        _updateState(chaiIn, yDaiIn);
    }

    /// @dev Mint liquidity tokens in exchange for adding chai and yDai
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

        // The operations below are bounded by what was transferred, so they can't overflow
        _updateState(chaiReserves + chaiOffered, yDaiReserves + yDaiRequired);
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

        // The operations below are bounded by what can be transferred and can't overflow
        _updateState(chaiReserves - chaiReturned, yDaiReserves - yDaiReturned);
    }

    /// @dev Sell Chai for yDai
    /// @param from Wallet providing the chai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param chaiIn Amount of chai being sold that will be taken from the user's wallet
    function sellChai(address from, address to, uint128 chaiIn)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
    {
        int128 c = int128((((now > _pot.rho()) ? _pot.drip() : _pot.chi()) << 64) / 10**27); // If chi is above 2**64 we've got a bigger problem than overflow
        uint128 chaiReserves = uint128(chai.balanceOf(address(this)));  // Unlikely the market will hold 2**128 chai
        uint128 yDaiReserves = uint128(yDai.balanceOf(address(this)));  // Unlikely the market will hold 2**128 yDai
        uint256 yDaiOut = YieldMath.yDaiOutForChaiIn(
            chaiReserves, yDaiReserves,
            chaiIn,
            uint128(maturity - now), k, c, g                            // Won't overflow unless we allow maturities beyond the death of the universe
        );

        chai.transferFrom(from, address(this), chaiIn);
        yDai.transfer(to, yDaiOut);

        // The operations below are bounded by what can be transferred and can't overflow
        _updateState(chaiReserves + chaiIn, yDaiReserves - yDaiOut);
    }

    /// @dev Buy Chai for yDai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the chai being bought
    /// @param chaiOut Amount of chai being bought that will be deposited in `to` wallet
    function buyChai(address from, address to, uint128 chaiOut)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
    {
        int128 c = int128((((now > _pot.rho()) ? _pot.drip() : _pot.chi()) << 64) / 10**27);
        uint128 chaiReserves = uint128(chai.balanceOf(address(this)));
        uint128 yDaiReserves = uint128(yDai.balanceOf(address(this)));
        uint256 yDaiIn = YieldMath.yDaiInForChaiOut(
            chaiReserves, yDaiReserves,
            chaiOut,
            uint128(maturity - now), k, c, g
        );

        yDai.transferFrom(from, address(this), yDaiIn);
        chai.transfer(to, chaiOut);

        // The operations below are bounded by what can be transferred and can't overflow
        _updateState(chaiReserves - chaiOut, yDaiReserves + yDaiIn);
    }

    /// @dev Sell yDai for Chai
    /// @param from Wallet providing the yDai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the chai being bought
    /// @param yDaiIn Amount of yDai being sold that will be taken from the user's wallet
    function sellYDai(address from, address to, uint128 yDaiIn)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
    {
        int128 c = int128((((now > _pot.rho()) ? _pot.drip() : _pot.chi()) << 64) / 10**27);
        uint128 chaiReserves = uint128(chai.balanceOf(address(this)));
        uint128 yDaiReserves = uint128(yDai.balanceOf(address(this)));
        uint256 chaiOut = YieldMath.chaiOutForYDaiIn(
            chaiReserves, yDaiReserves,
            yDaiIn,
            uint128(maturity - now), k, c, g
        );

        yDai.transferFrom(from, address(this), yDaiIn);
        chai.transfer(to, chaiOut);

        // The operations below are bounded by what can be transferred and can't overflow
        _updateState(chaiReserves - chaiOut, yDaiReserves + yDaiIn);
    }

    /// @dev Buy yDai for chai
    /// @param from Wallet providing the chai being sold. Must have approved the operator with `market.addDelegate(operator)`.
    /// @param to Wallet receiving the yDai being bought
    /// @param yDaiOut Amount of yDai being bought that will be deposited in `to` wallet
    function buyYDai(address from, address to, uint128 yDaiOut)
        external override
        onlyHolderOrDelegate(from, "Market: Only Holder Or Delegate")
    {
        int128 c = int128((((now > _pot.rho()) ? _pot.drip() : _pot.chi()) << 64) / 10**27);
        uint128 chaiReserves = uint128(chai.balanceOf(address(this)));
        uint128 yDaiReserves = uint128(yDai.balanceOf(address(this)));
        uint256 chaiIn = YieldMath.chaiInForYDaiOut(
            chaiReserves, yDaiReserves,
            yDaiOut,
            uint128(maturity - now), k, c, g
        );

        chai.transferFrom(from, address(this), chaiIn);
        yDai.transfer(to, yDaiOut);

        // The operations below are bounded by what can be transferred and can't overflow
        _updateState(chaiReserves + chaiIn, yDaiReserves - yDaiOut);
    }

    /// @dev Maintain the price oracle
    function _updateState(uint256 x0, uint256 y0) internal {
        State memory prevState = state;
        state = State({
            timestamp: uint32(block.timestamp % 2**32),
            accumulator: uint64(prevState.prevRate + (prevState.prevRate * (block.timestamp - prevState.timestamp)) / 10**27),
            prevRate: uint32(y0 * 10**27 / x0)
        });
    }
}