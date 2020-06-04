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
    IERC20 internal _token;                       // Weth or Chai
    IOracle internal _oracle;                     // WethOracle or ChaiOracle
    bytes32 public collateral;                    // "WETH" or "CHAI". Upgrade to 0.6.8 and make immutable
    mapping(address => uint256) public posted;    // In Weth or Chai
    mapping(address => uint256) public debtYDai;  // In yDai

    constructor (
        address treasury_,
        address dai_,
        address yDai_,
        address token_,
        address oracle_,
        bytes32 collateral_
    ) public {
        _treasury = ITreasury(treasury_);
        _dai = IERC20(dai_);
        _yDai = IYDai(yDai_);
        _token = IERC20(token_);
        _oracle = IOracle(oracle_);
        require(
            collateral_ == WETH || collateral_ == CHAI,
            "Dealer: Unsupported collateral"
        );
        collateral = collateral_;
    }

    /// @dev Maximum borrowing power of an user in dai for a given collateral
    //
    // powerOf[user](wad) = posted[user](wad) * oracle.price()(ray)
    //
    function powerOf(address user) public returns (uint256) {
        // dai = price * collateral
        return posted[user].muld(_oracle.price(), RAY);
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

    /// @dev Return if the borrowing power of an user is equal or greater than its debt
    function isCollateralized(address user) public returns (bool) {
        return powerOf(user) >= debtDai(user);
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

    /// @dev Takes collateral _token from `from` address
    // from --- Token ---> us
    function post(address from, uint256 amount) public virtual {
        require(
            _token.transferFrom(from, address(_treasury), amount),
            "Dealer: Collateral transfer fail"
        );
        if (collateral == WETH){
            _treasury.pushWeth();                          // Have Treasury process the weth
        } else if (collateral == CHAI) {
            _treasury.pushChai();
        } else {
            revert("Dealer: Unsupported collateral");
        }
        posted[from] = posted[from].add(amount);
    }

    /// @dev Returns collateral to `to` address
    // us --- Token ---> to
    function withdraw(address to, uint256 amount) public virtual {
        posted[to] = posted[to].sub(amount); // Will revert if not enough posted

        require(
            isCollateralized(to),
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
    function borrow(address to, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "Dealer: No mature borrow"
        );

        debtYDai[to] = debtYDai[to].add(yDai);

        require(
            isCollateralized(to),
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
    function repayYDai(address from, uint256 yDai) public {
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
    function repayDai(address from, uint256 dai) public {
        (uint256 toRepay, uint256 debtDecrease) = amounts(from, inYDai(dai));
        require(
            _dai.transferFrom(from, address(_treasury), toRepay),  // Take dai from user to Treasury
            "Dealer: Dai transfer fail"
        );

        _treasury.pushDai();                                      // Have Treasury process the dai
        debtYDai[from] = debtYDai[from].sub(debtDecrease);
    }

    /// @dev Moves all debt and weth from `from` in YDai to `to` in MakerDAO, denominated in Dai
    /// `to` needs to surround this call with `_vat.hope(address(_treasury))` and `_vat.nope(address(_treasury))`
    function split(address from, address to) public {
        require(
            collateral == WETH,
            "Dealer: Unsupported collateral for split"
        );
        _treasury.transferPosition(to, posted[from], debtDai(from));
        delete posted[from];
        delete debtYDai[from];
    }

    /// @dev Calculates the amount to repay and the amount by which to reduce the debt
    function amounts(address user, uint256 yDai) internal view returns(uint256, uint256) {
        uint256 toRepay = Math.min(yDai, debtDai(user));
        // TODO: Check if this can be taken from DecimalMath.sol
        // uint256 debtProportion = debtYDai[user].mul(RAY.unit())
        //     .divdr(debtDai(user).mul(RAY.unit()), RAY);
        uint256 debtProportion = divdrup( // TODO: Check it works if we are not rounding.
            debtYDai[user].mul(RAY.unit()),
            debtDai(user).mul(RAY.unit()),
            RAY
        );
        return (toRepay, toRepay.muld(debtProportion, RAY));
    }

    /// @dev Divides x between y, rounding up to the closest representable number.
    /// Assumes x and y are both fixed point with `decimals` digits.
     // TODO: Check if this needs to be taken from DecimalMath.sol
    function divdrup(uint256 x, uint256 y, uint8 decimals)
        internal pure returns (uint256)
    {
        uint256 z = x.mul((decimals + 1).unit()).div(y);
        if (z % 10 > 0) return z / 10 + 1;
        else return z / 10;
    }
}