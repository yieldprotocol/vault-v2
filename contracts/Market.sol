pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Market contract exchanges Dai for yDai at a price defined by a specific formula.
contract Market is Constants {
    using DecimalMath for uint256;
    using DecimalMath for uint8;
    using SafeMath for uint256;

    event Investment(address investor, uint256 sharesPurchased);
    event DaiToYDai(address trader, uint256 daiIn, uint256 yDaiOut);

    uint256 public constant FEE_RATE = 500;        // fee = 1/feeRate = 0.2%

    IERC20 public dai;
    IERC20 public yDai;

    uint256 public daiPool;
    uint256 public yDaiPool;
    uint256 public invariant;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    constructor(address dai_, address yDai_) public {
        dai = IERC20(dai_);
        yDai = IERC20(yDai_);
    }

    modifier initialized() {
        require(
            invariant > 0 && totalShares > 0,
            "Market: Not initialized"
        );
        _;
    }

    function initializeExchange(uint256 daiAmount, uint256 yDaiAmount) external {
        require(
            invariant == 0 && totalShares == 0,
            "Invariant or totalShares != 0"
        );
        // Prevents share cost from being too high or too low - potentially needs work
        require(
            daiAmount >= 10000 && yDaiAmount >= 10000,
            "Market: Initialization Parameters"
        );
        daiPool = daiAmount;
        yDaiPool = yDaiAmount;
        invariant = daiPool.mul(yDaiPool);
        shares[msg.sender] = 1000;
        totalShares = 1000;
        dai.transferFrom(msg.sender, address(this), daiAmount);
        yDai.transferFrom(msg.sender, address(this), yDaiAmount);
    }

    function investLiquidity(uint256 daiAmount, uint256 minShares) external initialized {
        require(
            daiAmount > 0 && minShares > 0,
            "Market: InvestDai Parameters"
        );
        uint256 daiPerShare = daiPool.div(totalShares);
        require(
            daiAmount >= daiPerShare,
            "Market: Not enough dai"
        );
        uint256 sharesPurchased = daiAmount.div(daiPerShare);
        require(
            sharesPurchased >= minShares,
            "Market: Not enough shares"
        );

        uint256 yDaiPerShare = yDaiPool.div(totalShares);
        uint256 yDaiRequired = sharesPurchased.mul(yDaiPerShare);
        shares[msg.sender] = shares[msg.sender].add(sharesPurchased);
        totalShares = totalShares.add(sharesPurchased);

        uint256 daiUsed = sharesPurchased.mul(daiPerShare);
        daiPool = daiPool.add(daiUsed);
        yDaiPool = yDaiPool.add(yDaiRequired);
        invariant = daiPool.mul(yDaiPool);
        dai.transferFrom(msg.sender, address(this), daiUsed);
        yDai.transferFrom(msg.sender, address(this), yDaiRequired);
        emit Investment(msg.sender, sharesPurchased);
    }

    function daiToYDai(uint256 daiSold, uint256 minYDaiReceived, uint256 timeout) external {
        require(
            daiSold > 0 && minYDaiReceived > 0 && now < timeout,
            "Market: DaiToYDai Parameters"
        );
        _daiToYDai(daiSold, minYDaiReceived);
    }

    function yDaiToDai(uint256 yDaiSold, uint256 minDaiReceived, uint256 timeout) external {
        require(
            yDaiSold > 0 && minDaiReceived > 0 && now < timeout,
            "Market: DaiToYDai Parameters"
        );
        _ydaiToDai(yDaiSold, minDaiReceived);
    }

    function _daiToYDai(uint256 daiIn, uint256 minYDaiOut) internal {
        uint256 fee = daiIn.div(FEE_RATE);
        uint256 newDaiPool = daiPool.add(daiIn);
        uint256 tempDaiPool = newDaiPool.sub(fee);
        uint256 newYDaiPool = invariant.div(tempDaiPool);
        uint256 yDaiOut = yDaiPool.sub(newYDaiPool);

        require(
            yDaiOut >= minYDaiOut,
            "Market: Not enough YDai"
        );

        daiPool = newDaiPool;
        yDaiPool = newYDaiPool;
        invariant = newYDaiPool.mul(newDaiPool); // TODO: Why do we do this?
        dai.transferFrom(msg.sender, address(this), daiIn);
        yDai.transfer(msg.sender, yDaiOut);

        emit DaiToYDai(msg.sender, daiIn, yDaiOut);
    }

    function _yDaiToDai(uint256 yDaiIn, uint256 minDaiOut) internal {
        uint256 fee = yDaiIn.div(FEE_RATE);
        uint256 newYDaiPool = yDaiPool.add(yDaiIn);
        uint256 tempYDaiPool = newYDaiPool.sub(fee);
        uint256 newDaiPool = invariant.div(tempYDaiPool);
        uint256 daiOut = daiPool.sub(newDaiPool);

        require(
            daiOut >= minDaiOut,
            "Market: Not enough Dai"
        )yDaiPool;

        yDaiPool = newYDaiPool;
        daiPool = newDaiPool;
        invariant = newDaiPool.mul(newYDaiPool); // TODO: Why do we do this?
        yDai.transferFrom(msg.sender, address(this), yDaiIn);
        dai.transfer(msg.sender, daiOut);

        emit YDaiToDai(msg.sender, yDaiIn, daiOut);
    }

    // TODO: mapping(address => uint256) public pools;
    function _swap(address t0, address t1, uint256 t0In, uint256 minT1Out) internal {
        require(
            t0 != t1 && pools[t0] != address(0) && pools[t1] != address(0),
            revert("Market: Token parameters");
        );

        uint256 fee = t0In.div(FEE_RATE);
        uint256 newT0Pool = pools[t0].add(t0In);
        uint256 tempT0Pool = newT0Pool.sub(fee);
        uint256 newT1Pool = invariant.div(tempT0Pool);
        uint256 t1Out = t1Pool.sub(newT1Pool);

        require(
            t1Out >= minT1Out,
            "Market: Not enough T1"
        );

        pools[t0] = newT0Pool;
        pools[t1] = newT1Pool;

        invariant = pools[t0].mul(pools[t1]); // TODO: Why do we do this?
        IERC20(t0).transferFrom(msg.sender, address(this), t0In);
        IERC20(t1).transfer(msg.sender, t1Out);

        emit YDaiToDai(msg.sender, yDaiIn, daiOut);
    }
}