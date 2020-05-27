pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IChai.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";


/// @dev A dealer takes collateral and issues yDai. There is one Dealer per series.
contract Dealer is Ownable, Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    bytes32 public constant WETH = "WETH"; // TODO: Upgrade to 0.6.9 and use immutable
    bytes32 public constant CHAI = "CHAI"; // TODO: Upgrade to 0.6.9 and use immutable

    ITreasury internal _treasury;
    IERC20 internal _dai;
    IYDai internal _yDai;

    mapping(bytes32 => IERC20) internal tokens;                           // Weth or Chai
    mapping(bytes32 => IOracle) internal oracles;                         // WethOracle or ChaiOracle
    mapping(bytes32 => mapping(address => uint256)) internal posted;     // In Weth or Chai, per collateral type
    mapping(bytes32 => mapping(address => uint256)) internal debtYDai;   // In yDai, per collateral type

    constructor (
        address treasury_,
        address dai_,
        address yDai_,
        address weth_,
        address wethOracle_,
        address chai_,
        address chaiOracle_
    ) public {
        _treasury = ITreasury(treasury_);
        _dai = IERC20(dai_);
        _yDai = IYDai(yDai_);
        tokens[WETH] = IERC20(weth_);
        oracles[WETH] = IOracle(wethOracle_);
        tokens[CHAI] = IERC20(chai_);
        oracles[CHAI] = IOracle(chaiOracle_);
    }

    /// @dev Maximum borrowing power of an user in dai for a given collateral
    //
    //                        posted[user](wad)
    // powerOf[user](wad) = ---------------------
    //                       oracle.price()(ray)
    //
    function powerOf(bytes32 collateral, address user) public returns (uint256) {
        // collateral = dai * price
        return posted[collateral][user].divd(oracles[collateral].price(), RAY);
    }

    /// @dev Return debt in dai of an user
    //
    //                        rate_now
    // debt_now = debt_mat * ----------
    //                        rate_mat
    //
    function debtDai(bytes32 collateral, address user) public view returns (uint256) {
        return inDai(debtYDai[collateral][user]);
    }

    /// @dev Return if the borrowing power of an user is equal or greater than its debt
    function isCollateralized(bytes32 collateral, address user) public returns (bool) {
        return powerOf(collateral, user) >= debtDai(collateral, user);
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
    function post(bytes32 collateral, address from, uint256 amount) public virtual {
        require(
            tokens[collateral].transferFrom(from, address(_treasury), amount),
            "Dealer: Collateral transfer fail"
        );
        if (collateral == WETH){
            _treasury.pushWeth();                          // Have Treasury process the weth
        } else if (collateral == CHAI) {
            _treasury.pushChai();
        } else {
            revert("Dealer: Unsupported collateral");
        }
        posted[collateral][from] = posted[collateral][from].add(amount);
    }

    /// @dev Returns collateral to `to` address
    // us --- Token ---> to
    function withdraw(bytes32 collateral, address to, uint256 amount) public virtual {
        posted[collateral][to] = posted[collateral][to].sub(amount); // Will revert if not enough posted

        require(
            isCollateralized(collateral, to),
            "Dealer: Free more collateral"
        );

        if (collateral == WETH){
            _treasury.pullWeth(to, amount);                          // Take weth from Treasury and give it to `to`
        } else if (collateral == CHAI) {
            _treasury.pullChai(to, amount);
        } else {
            revert("Dealer: Unsupported collateral");
        }
    }

    /// @dev Mint yDai for address `to` by locking its market value in collateral, user debt is increased.
    //
    // posted[user](wad) >= (debtYDai[user](wad)) * amount (wad)) * collateralization (ray)
    //
    // us --- yDai ---> user
    // debt++
    function borrow(bytes32 collateral, address to, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "Dealer: No mature borrow"
        );

        debtYDai[collateral][to] = debtYDai[collateral][to].add(yDai);

        require(
            isCollateralized(collateral, to),
            "Dealer: Post more collateral"
        );

        _yDai.mint(to, yDai);
    }

    /// @dev Burns yDai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- yDai ---> us
    // debt--
    function repayYDai(bytes32 collateral, address from, uint256 yDai) public {
        (uint256 toRepay, uint256 debtDecrease) = amounts(from, collateral, yDai);
        _yDai.burn(from, toRepay);
        debtYDai[collateral][from] = debtYDai[collateral][from].sub(debtDecrease);
    }

    /// @dev Takes dai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- dai ---> us
    // debt--
    function repayDai(bytes32 collateral, address from, uint256 dai) public {
        (uint256 toRepay, uint256 debtDecrease) = amounts(from, collateral, inYDai(dai));
        require(
            _dai.transferFrom(from, address(_treasury), toRepay),  // Take dai from user to Treasury
            "Dealer: Dai transfer fail"
        );

        _treasury.pushDai();                                      // Have Treasury process the dai
        debtYDai[collateral][from] = debtYDai[collateral][from].sub(debtDecrease);
    }

    /// @dev Calculates the amount to repay and the amount by which to reduce the debt
    function amounts(address user, bytes32 collateral, uint256 yDai) internal view returns(uint256, uint256) {
        uint256 toRepay = Math.min(yDai, debtDai(collateral, user));
        uint256 debtProportion = debtYDai[collateral][user].mul(RAY.unit())
            .divd(debtDai(collateral, user).mul(RAY.unit()), RAY);
        return (toRepay, toRepay.muld(debtProportion, RAY));
    }
}