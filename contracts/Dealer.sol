pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IChai.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";


/// @dev A dealer takes collateral and issues yDai. There is one Dealer per series.
contract Dealer is AuthorizedAccess(), Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    event Settled(uint256 indexed maturity, address indexed user, uint256 debt, uint256 tokens);
    event Grabbed(address indexed user, uint256 tokens);

    bytes32 public constant WETH = "WETH"; // TODO: Upgrade to 0.6.9 and use immutable
    bytes32 public constant CHAI = "CHAI"; // TODO: Upgrade to 0.6.9 and use immutable

    ITreasury internal _treasury;
    IERC20 internal _dai;
    IERC20 internal _token;                       // Weth or Chai
    IOracle internal _oracle;                     // WethOracle or ChaiOracle
    bytes32 public collateral;                    // "WETH" or "CHAI". Upgrade to 0.6.8 and make immutable
    mapping(address => uint256) public posted;    // In Weth or Chai
    mapping(uint256 => IYDai) public series;      // YDai series, indexed by maturity
    uint256[] internal seriesIterator;            // We need to know all the series
    mapping(uint256 => mapping(address => uint256)) public debtYDai;  // By series, in yDai

    constructor (
        address treasury_,
        address dai_,
        address token_,
        address oracle_,
        bytes32 collateral_
    ) public {
        _treasury = ITreasury(treasury_);
        _dai = IERC20(dai_);
        _token = IERC20(token_);
        _oracle = IOracle(oracle_);
        require(
            collateral_ == WETH || collateral_ == CHAI,
            "Dealer: Unsupported collateral"
        );
        collateral = collateral_;
    }

    /// @dev Returns if a series has been added to the Dealer, for a given series identified by maturity
    function containsSeries(uint256 maturity) public view returns (bool) {
        return address(series[maturity]) != address(0);
    }

    /// @dev Adds an yDai series to this Dealer
    function addSeries(address yDaiContract) public onlyOwner {
        uint256 maturity = IYDai(yDaiContract).maturity();
        require(
            !containsSeries(maturity),
            "Dealer: Series already added"
        );
        series[maturity] = IYDai(yDaiContract);
        seriesIterator.push(maturity);
    }

    /// @dev Maximum borrowing power of an user in dai for a given collateral
    //
    // powerOf[user](wad) = posted[user](wad) * oracle.price()(ray)
    //
    function powerOf(address user) public returns (uint256) {
        // dai = price * collateral
        return posted[user].muld(_oracle.price(), RAY);
    }

    /// @dev Returns the total debt of an user, across all series, in yDai
    function totalDebtYDai(address user) public view returns (uint256) {
        uint256 totalDebt;
        for (uint256 i = 0; i < seriesIterator.length; i += 1) {
            totalDebt = totalDebt + debtYDai[seriesIterator[i]][user];
        } // We don't expect hundreds of maturities per dealer
        return totalDebt;
    }

    /// @dev Return if the borrowing power of an user is equal or greater than its debt
    function isCollateralized(address user) public returns (bool) {
        return powerOf(user) >= totalDebtDai(user);
    }

    /// @dev Returns the dai equivalent of an yDai amount, for a given series identified by maturity
    function inDai(uint256 maturity, uint256 yDaiAmount) public view returns (uint256) {
        require(
            containsSeries(maturity),
            "Dealer: Unrecognized series"
        );
        if (series[maturity].isMature()){
            return yDaiAmount.muld(series[maturity].rate(), RAY);
        }
        else {
            return yDaiAmount;
        }
    }

    /// @dev Returns the yDai equivalent of a dai amount, for a given series identified by maturity
    function inYDai(uint256 maturity, uint256 daiAmount) public view returns (uint256) {
        require(
            containsSeries(maturity),
            "Dealer: Unrecognized series"
        );
        if (series[maturity].isMature()){
            return daiAmount.divd(series[maturity].rate(), RAY);
        }
        else {
            return daiAmount;
        }
    }

    /// @dev Return debt in dai of an user, for a given series identified by maturity
    //
    //                        rate_now
    // debt_now = debt_mat * ----------
    //                        rate_mat
    //
    function debtDai(uint256 maturity, address user) public view returns (uint256) {
        return inDai(maturity, debtYDai[maturity][user]);
    }

    /// @dev Returns the total debt of an user, across all series, in Dai
    function totalDebtDai(address user) public view returns (uint256) {
        uint256 totalDebt;
        for (uint256 i = 0; i < seriesIterator.length; i += 1) {
            totalDebt = totalDebt + debtDai(seriesIterator[i], user);
        } // We don't expect hundreds of maturities per dealer
        return totalDebt;
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
    function borrow(uint256 maturity, address to, uint256 yDaiAmount) public {
        require(
            containsSeries(maturity),
            "Dealer: Unrecognized series"
        );
        require(
            series[maturity].isMature() != true,
            "Dealer: No mature borrow"
        );

        debtYDai[maturity][to] = debtYDai[maturity][to].add(yDaiAmount);

        require(
            isCollateralized(to),
            "Dealer: Post more collateral"
        );

        series[maturity].mint(to, yDaiAmount);
    }

    /// @dev Burns yDai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- yDai ---> us
    // debt--
    function repayYDai(uint256 maturity, address from, uint256 yDaiAmount) public {
        require(
            containsSeries(maturity),
            "Dealer: Unrecognized series"
        );
        (uint256 toRepay, uint256 debtDecrease) = amounts(maturity, from, yDaiAmount);
        series[maturity].burn(from, toRepay);
        debtYDai[maturity][from] = debtYDai[maturity][from].sub(debtDecrease);
    }

    /// @dev Takes dai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- dai ---> us
    // debt--
    function repayDai(uint256 maturity, address from, uint256 daiAmount) public {
        (uint256 toRepay, uint256 debtDecrease) = amounts(maturity, from, inYDai(maturity, daiAmount));
        require(
            _dai.transferFrom(from, address(_treasury), toRepay),  // Take dai from user to Treasury
            "Dealer: Dai transfer fail"
        );

        _treasury.pushDai();                                      // Have Treasury process the dai
        debtYDai[maturity][from] = debtYDai[maturity][from].sub(debtDecrease);
    }

    /// @dev Erases a debt position and its equivalent amount of collateral from the user records
    function settle(uint256 maturity, address user)
        public onlyAuthorized("Dealer: Not Authorized") returns (uint256, uint256) {
        uint256 price = _oracle.price();
        uint256 debt = debtDai(maturity, user);
        uint256 tokenAmount = divdrup(debt, price, RAY);
        posted[user] = posted[user].sub(tokenAmount);
        delete debtYDai[maturity][user];
        emit Settled(maturity, user, debt, tokenAmount);
        return (tokenAmount, debt);
    }

    /// @dev Removes an amount from the user collateral records in dealer. Can only be called with no YDai debt.
    /// `to` needs to surround this call with `_vat.hope(address(_treasury))` and `_vat.nope(address(_treasury))`
    function grab(address user, uint256 amount)
        public onlyAuthorized("Dealer: Not Authorized") {
        require(
            totalDebtYDai(user) == 0,
            "Dealer: Settle all debt first"
        );
        posted[user] = posted[user].sub(amount, "Dealer: Not enough collateral");
        emit Grabbed(user, amount);
    }

    /// @dev Calculates the amount to repay and the amount by which to reduce the debt
    function amounts(uint256 maturity, address user, uint256 yDaiAmount) internal view returns(uint256, uint256) {
        uint256 toRepay = Math.min(yDaiAmount, debtDai(maturity, user));
        // TODO: Check if this can be taken from DecimalMath.sol
        // uint256 debtProportion = debtYDai[user].mul(RAY.unit())
        //     .divdr(debtDai(user).mul(RAY.unit()), RAY);
        uint256 debtProportion = divdrup( // TODO: Check it works if we are not rounding.
            debtYDai[maturity][user].mul(RAY.unit()),
            debtDai(maturity, user).mul(RAY.unit()),
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