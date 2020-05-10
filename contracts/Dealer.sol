pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";


/// @dev A dealer takes one type of collateral token and issues yDai
contract Dealer is Ownable, Constants {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    IYDai internal _yDai;
    IERC20 internal _token;
    IOracle internal _tokenOracle; // The oracle should return the price adjusted by collateralization

    mapping(address => uint256) internal posted; // In Erc20
    mapping(address => uint256) internal debt;   // In Dai/yDai

    constructor (
        address yDai_,
        address token_,
        address tokenOracle_
    ) public {
        _yDai = YDai(yDai_);
        _token = IERC20(token_);
        _tokenOracle = IOracle(tokenOracle_);
    }

    /// @dev Collateral not in use for debt
    //
    //                       debtOf(user)(wad)
    // posted[user](wad) - -----------------------
    //                       daiOracle.get()(ray)
    //
    function unlockedOf(address user) public returns (uint256) {
        uint256 locked = debtOf(user)
            .divd(_tokenOracle.price(), RAY);
        if (locked > posted[user]) return 0; // Unlikely
        return posted[user].sub(locked);
    }

    /// @dev Return debt in underlying of an user
    //
    //                        rate_now
    // debt_now = debt_mat * ----------
    //                        rate_mat
    //
    function debtOf(address user) public view returns (uint256) {
        if (_yDai.isMature()){
            return debt[user].muld(_yDai.rate(), RAY);
        }
        else {
            return debt[user];
        }
    }

    /// @dev Takes collateral tokens from `from` address
    // from --- Token ---> us
    function post(address from, uint256 token) public {
        require(
            _token.transferFrom(from, token),
            "Dealer: Collateral transfer fail"
        );
        posted[from] = posted[from].add(token);
    }

    /// @dev Returns collateral to `to` address
    // us --- Token ---> to
    function withdraw(address to, uint256 token) public {
        require(
            unlockedOf(to) >= token,
            "Dealer: Free more collateral"
        );
        posted[to] = posted[to].sub(token); // Will revert if not enough posted
        require(
            _token.transfer(to, token),
            "Dealer: Collateral transfer fail"
        );
    }

    /// @dev Mint yDai for address `to` by locking its market value in collateral, user debt is increased.
    //
    // posted[user](wad) >= (debt[user](wad)) * amount (wad)) * collateralization (ray)
    //
    // us --- yDai ---> user
    // debt++
    function borrow(address to, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "Dealer: No mature borrow"
        );
        require(
            posted[to] >= (debtOf(to).add(yDai))
                .divd(_tokenOracle.price(), RAY),
            "Dealer: Post more collateral"
        );
        debt[to] = debt[to].add(yDai);
        _yDai.mint(to, yDai);
    }

    /// @dev Burns yDai from `from` address, user debt is decreased.
    //                                                  debt_maturity
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_nominal
    //
    // user --- Dai ---> us
    // debt--
    function repay(address from, uint256 yDai) public {
        uint256 debtProportion = debt[from].mul(RAY.unit())
            .divd(debtOf(from).mul(RAY.unit()), RAY);
        _yDai.burn(from, yDai);
        debt[from] = debt[from].sub(yDai.muld(debtProportion, RAY)); // Will revert if not enough debt
    }
}