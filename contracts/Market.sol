pragma solidity ^0.6.2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Market contract exchanges Dai for yDai at a price defined by a specific formula.
contract Market is ERC20, Constants {
    using SafeMath for uint256;

    struct State {
        uint32 timestamp;    // last time contract was updated. wraps around after 2^32
        uint32 prevRate;     // UQ16x16 interest rate last time the contract was updated
        uint64 accumulator;  // interest rate oracle accumulator—32 bits for a UQ16x16, 32 bits for overflow
    }

    uint256 constant initialSupply = 1000;

    IERC20 public chai;
    IERC20 public yDai;

    constructor(address chai_, address yDai_) public ERC20("Name", "Symbol") {
        chai = IERC20(chai_);
        yDai = IERC20(yDai_);
    }

    function init(uint256 chaiIn, uint256 yDaiIn) external {
        require(
            totalSupply() == 0,
            revert("Market: Already initialized")
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
        uint256 tokensMinted = supply.mul(chaiOffered).div(chai.balanceOf(address(this));
        uint256 yDaiRequired = supply.mul(tokensMinted).div(yDai.balanceOf(address(this));

        chai.transferFrom(msg.sender, address(this), chaiOffered);
        yDai.transferFrom(msg.sender, address(this), yDaiRequired);
        _mint(msg.sender, tokensMinted);

        _updateState(chai.balanceOf(address(this)), yDai.balanceOf(address(this)));
    }

    /// @dev Burn liquidity tokens in exchange for chai and yDai
    function burn(uint256 tokensBurned) external {
        uint256 supply = totalSupply();

        _burnFrom(msg.sender, tokensBurned);
        chai.transfer(msg.sender, tokensBurned.mul(chai.balanceOf(address(this))).div(supply));
        yDai.transfer(msg.sender, tokensBurned.mul(yDai.balanceOf(address(this))).div(supply));

        _updateState(chai.balanceOf(address(this)), yDai.balanceOf(address(this)));
    }

    /// @dev Swap Chai for yDai
    function swapChaiForYDai(uint256 chaiIn) external { // TODO: Add `from` and `to` parameters

        uint256 fee = feeChaiForYDai();
        uint256 newChaiBalance = chai.balanceOf(address(this)).add(chaiIn).sub(fee);
        uint256 newYDaiBalance = reciprocalBalance(newChaiBalance);
        uint256 yDaiOut = yDai.balanceOf(address(this)).sub(newYDaiBalance);

        chai.transferFrom(msg.sender, address(this), chaiIn);
        yDai.transfer(msg.sender, yDaiOut);

        _updateState(newChaiBalance, newYDaiBalance);
    }

    /// @dev Swap yDai for Chai
    function swapYDaiForChai(uint256 yDaiIn) external { // TODO: Add `from` and `to` parameters

        uint256 fee = feeYDaiForChai();
        uint256 newYDaiBalance = yDai.balanceOf(address(this)).add(yDaiIn).sub(fee);
        uint256 newChaiBalance = reciprocalBalance(newYDaiBalance);
        uint256 chaiOut = chai.balanceOf(address(this)).sub(newChaiBalance);

        yDai.transferFrom(msg.sender, address(this), yDaiIn);
        chai.transfer(msg.sender, chaiOut);

        _updateState(newChaiBalance, newYDaiBalance);
    }

    /// @dev For the balance passed as an argument, returns the size of the reciprocal balance
    function reciprocalBalance(uint256 balance) public returns(uint256) {
        return balance; // TODO: Magic!
    }

    /// @dev Returns the fee for an yDai to Chai swap
    function feeYDaiForChai(uint256 yDaiIn) public returns(uint256) {
        return yDaiIn / 1000; // TODO: Magic!
    }

    /// @dev Returns the fee for an Chai to yDai swap
    function feeChaiForDai(chaiIn) public returns(uint256) {
        return chaiIn / 1000; // TODO: Magic!
    }

    /// @dev For the balance passed as an argument, returns the size of the reciprocal balance
    function reciprocalBalance(uint256 balance) public returns(uint256) {
        return balance; // TODO: Magic!
    }

    // TODO: What is this?
    function _updateState(uint256 x0, uint256 y0) internal {
        State memory prevState = state;
        state = State({
            timestamp: uint32(block.timestamp % 2**32),
            accumulator: uint64(prevState.prevRate + (prevState.prevRate * (block.timestamp - prevState.timestamp)) / RAY.unit()),
            prevRate: uint32(y0 * RAY.unit() / x0)
        });
    }
}