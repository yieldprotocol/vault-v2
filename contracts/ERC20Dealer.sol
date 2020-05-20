pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";


/// @dev A dealer takes one type of collateral token and issues yDai
contract ERC20Dealer is Ownable, Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    ITreasury internal _treasury;
    IERC20 internal _dai;
    IYDai internal _yDai;
    IERC20 internal _token;
    IOracle internal _tokenOracle; // The oracle should return the price adjusted by collateralization

    mapping(address => uint256) internal posted;     // In Erc20
    mapping(address => uint256) internal debtYDai;   // In yDai

    constructor (
        address treasury_,
        address dai_,
        address yDai_,
        address token_,
        address tokenOracle_
    ) public {
        _treasury = ITreasury(treasury_);
        _dai = IERC20(dai_);
        _yDai = IYDai(yDai_);
        _token = IERC20(token_);
        _tokenOracle = IOracle(tokenOracle_);
    }

    /// @dev Maximum borrowing power of an user in dai
    //
    //                        posted[user](wad)
    // powerOf[user](wad) = ---------------------
    //                       oracle.price()(ray)
    //
    function powerOf(address user) public returns (uint256) {
        // collateral = dai * price
        return posted[user].divd(_tokenOracle.price(), RAY);
    }

    /// @dev Return debt in dai of an user
    //
    //                        rate_now
    // debt_now = debt_mat * ----------
    //                        rate_mat
    //
    function debtDai(address user) public view returns (uint256) {
        return inDai(debtYDai[user]);
    }

    /// @dev Returns the dai equivalent of an yDai amount
    function inDai(uint256 yDai) public view returns (uint256) {
        if (_yDai.isMature()){
            return yDai.muld(_yDai.rate(), RAY);
        }
        else {
            return yDai;
        }
    }

    /// @dev Returns the yDai equivalent of a dai amount
    function inYDai(uint256 dai) public view returns (uint256) {
        if (_yDai.isMature()){
            return dai.divd(_yDai.rate(), RAY);
        }
        else {
            return dai;
        }
    }

    /// @dev Takes collateral tokens from `from` address
    // from --- Token ---> us
    function post(address from, uint256 token) public virtual {
        require(
            _token.transferFrom(from, address(this), token),
            "ERC20Dealer: Collateral transfer fail"
        );
        posted[from] = posted[from].add(token);
    }

    /// @dev Returns collateral to `to` address
    // us --- Token ---> to
    function withdraw(address to, uint256 token) public virtual {
        require(
            powerOf(to) >= debtDai(to),
            "ERC20Dealer: Undercollateralized"
        );
        require( // (power - debt) * price
            (powerOf(to) - debtDai(to)).muld(_tokenOracle.price(), RAY) >= token, // SafeMath not needed
            "ERC20Dealer: Free more collateral"
        );
        posted[to] = posted[to].sub(token); // Will revert if not enough posted
        require(
            _token.transfer(to, token),
            "ERC20Dealer: Collateral transfer fail"
        );
    }

    /// @dev Mint yDai for address `to` by locking its market value in collateral, user debt is increased.
    //
    // posted[user](wad) >= (debtYDai[user](wad)) * amount (wad)) * collateralization (ray)
    //
    // us --- yDai ---> user
    // debt++
    function borrow(address to, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "ERC20Dealer: No mature borrow"
        );
        require( // collateral = dai * price
            posted[to] >= (debtDai(to).add(yDai))
                .muld(_tokenOracle.price(), RAY),
            "ERC20Dealer: Post more collateral"
        );
        debtYDai[to] = debtYDai[to].add(yDai);
        _yDai.mint(to, yDai);
    }

    /// @dev Burns yDai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- yDai ---> us
    // debt--
    function restore(address from, uint256 yDai) public {
        (uint256 toRepay, uint256 debtDecrease) = amounts(from, yDai);
        _yDai.burn(from, toRepay);
        debtYDai[from] = debtYDai[from].sub(debtDecrease);
    }

    /// @dev Takes dai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- dai ---> us
    // debt--
    function repay(address from, uint256 dai) public {
        require(
            _dai.transferFrom(from, address(this), dai),       // Take dai from user
            "ERC20Dealer: Dai transfer fail"
        );

        (uint256 toRepay, uint256 debtDecrease) = amounts(from, inYDai(dai));
        _dai.approve(address(_treasury), toRepay);              // Treasury will take the dai
        _treasury.push(address(this), toRepay);                 // Give the dai to Treasury
        debtYDai[from] = debtYDai[from].sub(debtDecrease);
    }

    /// @dev Calculates the amount to repay and the amount by which to reduce the debt
    function amounts(address user, uint256 yDai) internal view returns(uint256, uint256) {
        uint256 toRepay = Math.min(yDai, debtDai(user));
        uint256 debtProportion = debtYDai[user].mul(RAY.unit())
            .divd(debtDai(user).mul(RAY.unit()), RAY);
        return (toRepay, toRepay.muld(debtProportion, RAY));
    }
}