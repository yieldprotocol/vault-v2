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

    mapping(address => uint256) internal _posted; // In Erc20
    mapping(address => uint256) internal _debt;   // In Dai/yDai

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

    /// @dev Posted collateral
    function postedOf(address user) public returns (uint256) {
        return _posted[user];
    }

    /// @dev Maximum borrowing power of an user in dai
    //
    //                        _posted[user](wad)
    // powerOf[user](wad) = ---------------------
    //                       oracle.price()(ray)
    //
    function powerOf(address user) public returns (uint256) {
        // collateral = dai * price
        return _posted[user].divd(_tokenOracle.price(), RAY);
    }

    /// @dev Return debt in underlying of an user
    //
    //                        rate_now
    // debt_now = debt_mat * ----------
    //                        rate_mat
    //
    function debtOf(address user) public view returns (uint256) {
        if (_yDai.isMature()){
            return _debt[user].muld(_yDai.rate(), RAY);
        }
        else {
            return _debt[user];
        }
    }

    /// @dev Takes collateral tokens from `from` address
    // from --- Token ---> us
    function post(address from, uint256 token) public virtual {
        require(
            _token.transferFrom(from, address(this), token),
            "ERC20Dealer: Collateral transfer fail"
        );
        _posted[from] = _posted[from].add(token);
    }

    /// @dev Returns collateral to `to` address
    // us --- Token ---> to
    function withdraw(address to, uint256 token) public virtual {
        require(
            powerOf(to) >= debtOf(to),
            "ERC20Dealer: Undercollateralized"
        );
        require( // (power - debt) * price
            (powerOf(to) - debtOf(to)).muld(_tokenOracle.price(), RAY) >= token, // SafeMath not needed
            "ERC20Dealer: Free more collateral"
        );
        _posted[to] = _posted[to].sub(token); // Will revert if not enough posted
        require(
            _token.transfer(to, token),
            "ERC20Dealer: Collateral transfer fail"
        );
    }

    /// @dev Mint yDai for address `to` by locking its market value in collateral, user debt is increased.
    //
    // _posted[user](wad) >= (_debt[user](wad)) * amount (wad)) * collateralization (ray)
    //
    // us --- yDai ---> user
    // debt++
    function borrow(address to, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "ERC20Dealer: No mature borrow"
        );
        require( // collateral = dai * price
            _posted[to] >= (debtOf(to).add(yDai))
                .muld(_tokenOracle.price(), RAY),
            "ERC20Dealer: Post more collateral"
        );
        _debt[to] = _debt[to].add(yDai);
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
        uint256 toRepay = Math.min(yDai, debtOf(from));
        uint256 debtProportion = _debt[from].mul(RAY.unit())
            .divd(debtOf(from).mul(RAY.unit()), RAY);

        _yDai.burn(from, toRepay);
        _debt[from] = _debt[from].sub(toRepay.muld(debtProportion, RAY)); // Will revert if not enough debt
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

        uint256 toRepay = Math.min(dai, debtOf(from));
        uint256 debtProportion = _debt[from].mul(RAY.unit())
            .divd(debtOf(from).mul(RAY.unit()), RAY);

        _dai.approve(address(_treasury), toRepay);              // Treasury will take the dai
        _treasury.push(address(this), toRepay);                 // Give the dai to Treasury
        _debt[from] = _debt[from].sub(toRepay.muld(debtProportion, RAY)); // Will revert if not enough debt
    }

    /// @dev Calculates the amount to repay and the amount by which to reduce the debt
    function amounts(address user, uint256 dai) internal view returns(uint256, uint256) {
        uint256 toRepay = Math.min(dai, debtOf(user));
        uint256 debtProportion = _debt[user].mul(RAY.unit())
            .divd(debtOf(user).mul(RAY.unit()), RAY);
        return (toRepay, toRepay.muld(debtProportion, RAY));
    }
}