pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Market contract exchanges Dai for yDai at a price defined by a specific formula.
contract Market is ERC20, Constants {
    using DecimalMath for uint256;
    using DecimalMath for uint8;
    using SafeMath for uint256;

    event Investment(address investor, uint256 sharesPurchased);
    event Swap(
        address indexed trader,
        address indexed tokenSold,
        address indexed tokenReceived,
        uint256 tokensIn,
        uint256 tokensOut
    );

    uint256 public constant FEE_RATE = 500;        // fee = 1/feeRate = 0.2%

    IERC20 public t0; // Dai
    IERC20 public t1; // yDai

    uint256 internal _invariant;
    bool setup = true;

    mapping(address => uint256) public pools;

    constructor(address t0_, address t1_) public ERC20("Name", "Symbol") {
        t0 = IERC20(t0_);
        t1 = IERC20(t1_);
    }

    function init(uint256 t0Amount, uint256 t1Amount) external {
        /* require(
            setup,
            revert("Market: Already initialized")
        ); */ // TODO: Find out syntax issue
        require( // Prevents share cost from being too high or too low - potentially needs work
            t0Amount >= 10000 && t1Amount >= 10000,
            "Market: Initialization Parameters"
        );
        delete setup;
        pools[address(t0)] = t0Amount;
        pools[address(t1)] = t1Amount;

        _invariant = t0Amount.mul(t1Amount);
        _mint(msg.sender, 1000);

        t0.transferFrom(msg.sender, address(this), t0Amount);
        t1.transferFrom(msg.sender, address(this), t1Amount);
    }

    /// @dev Mint liquidity tokens in exchange for adding liquidity
    /// The parameter passed is the amount of `t0` being invested, an appropriate amount of `t1` to be invested alongside will be calculated and taken by this function from the caller.
    function mint(uint256 t0Amount, uint256 minShares) external {
        require(
            t0Amount > 0 && minShares > 0,
            "Market: InvestDai Parameters"
        );
        address t0Address = address(t0);
        address t1Address = address(t1);

        uint256 t0PerShare = pools[t0Address].div(totalSupply());
        require(
            t0Amount >= t0PerShare,
            "Market: Not enough t0 tokens"
        );
        uint256 sharesPurchased = t0Amount.div(t0PerShare); // TODO: I'm just letting this revert if not initialized
        require(
            sharesPurchased >= minShares,
            "Market: Not enough shares"
        );

        uint256 t1PerShare = pools[t1Address].div(totalSupply());
        uint256 t1Required = sharesPurchased.mul(t1PerShare);
        _mint(msg.sender, sharesPurchased);

        uint256 t0Used = sharesPurchased.mul(t0PerShare);
        pools[t0Address] = pools[t0Address].add(t0Used);
        pools[t1Address] = pools[t1Address].add(t1Required);
        _invariant = pools[t0Address].mul(pools[t1Address]);
        t0.transferFrom(msg.sender, address(this), t0Used);
        t1.transferFrom(msg.sender, address(this), t1Required);
        emit Investment(msg.sender, sharesPurchased);
    }

    /// @dev The `tInAddress` and `tOutAddress` can match `t0` and `t1` to sell `t0` tokens for `t1` tokens, or they can be reversed to sell `t1` for `t0`
    function swap(address tInAddress, address tOutAddress, uint256 tInAmount, uint256 minTOutAmount, uint256 timeout) external {
        require(
            now < timeout,
            "Market: Timeout expired"
        );
        /* require(
            tInAddress != tOutAddress && pools[tInAddress] != 0 && pools[tOutAddress] != 0,
            revert("Market: Token parameters")
        ); */ // TODO: Find out syntax issue

        uint256 fee = tInAmount.div(FEE_RATE);
        uint256 newTInPool = pools[tInAddress].add(tInAmount);
        uint256 tempTInPool = newTInPool.sub(fee);
        uint256 newTOutPool = reciprocalPool(tempTInPool);
        uint256 tOutAmount = pools[tOutAddress].sub(newTOutPool);

        require(
            tOutAmount >= minTOutAmount,
            "Market: Not enough TOut tokens"
        );

        pools[tInAddress] = newTInPool;
        pools[tOutAddress] = newTOutPool;

        _invariant = pools[tInAddress].mul(pools[tOutAddress]); // TODO: Why do we do this?
        IERC20(tInAddress).transferFrom(msg.sender, address(this), tInAmount);
        IERC20(tOutAddress).transfer(msg.sender, tOutAmount);

        emit Swap(msg.sender, tInAddress, tOutAddress, tInAmount, tOutAmount);
    }

    /// @dev For the pool passed as an argument, returns the size of the reciprocal pool
    function reciprocalPool(uint256 pool) public returns(uint256) {
        return _invariant.div(pool);
    }
}