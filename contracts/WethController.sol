pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ILender.sol";
import "./interfaces/ISaver.sol";
import "./Constants.sol";
import "./YDai.sol"; // TODO: Find how to use an interface


/// @dev WethController manages a Weth/yDai series pair
contract WethController is Ownable, Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;

    ILender internal _lender;
    ISaver internal _saver;
    YDai internal _yDai;
    IERC20 internal _weth;
    IOracle internal _wethOracle;

    mapping(address => uint256) internal posted; // In WETH
    mapping(address => uint256) internal debt; // In DAI

    uint256 public _stability; // accumulator (for stability fee) at maturity in RAY units
    uint256 public _collateralization; // accumulator (for stability fee) at maturity in RAY units

    constructor (
        address lender_,
        address saver_,
        address yDai_,
        address weth_,
        address wethOracle_,
        uint256 collateralization_
    ) public {
        _lender = ILender(lender_);
        _saver = ISaver(saver_);
        _yDai = YDai(yDai_);
        _weth = IERC20(weth_);
        _wethOracle = IOracle(wethOracle_);
        _collateralization = collateralization_;
    }

    /// @dev Collateral not in use for debt
    //
    //                       debtOf(user)(wad)
    // posted[user](wad) - -----------------------
    //                       daiOracle.get()(ray)
    //
    function unlockedOf(address user) public view returns (uint256) {
        uint256 locked = debtOf(user)
            .divd(_wethOracle.price(), RAY)
            .muld(_collateralization, RAY);
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
            (, uint256 rate,,,) = _vat.ilks("ETH-A"); // What would this be?
            return debt[user].muld(rate.divd(_yDai.rate(), RAY), RAY);
        } else {
            return debt[user];
        }
    }

    /// @dev Takes Weth as collateral from caller and gives it to the Lender
    // caller --- Weth ---> us
    function post(uint256 weth) public {
        post(msg.sender, weth);
    }

    /// @dev Takes Weth as collateral from `from` address and gives it to the Lender
    // from --- Weth ---> us
    function post(address from, uint256 weth) public {
        _lender.post(weth);
        posted[from] = posted[from].add(weth);
    }

    /// @dev Moves Weth collateral from Lender to caller
    // us --- Weth ---> caller
    function withdraw(uint256 weth) public {
        withdraw(msg.sender, weth);
    }

    /// @dev Moves Weth collateral from Lender to `to` address
    // us --- Weth ---> to
    function withdraw(address to, uint256 weth) public {
        require(
            unlockedOf(to) >= weth,
            "Accounts: Free more collateral"
        );
        posted[to] = posted[to].sub(weth); // Will revert if not enough posted
        _lender.withdraw(to, weth);
    }

    /// @dev Mint yTokens for caller by locking its market value in collateral, user debt is increased.
    function borrow(uint256 yDai) public {
        borrow(msg.sender, yDai);
    }

    /// @dev Mint yTokens for address `to` by locking its market value in collateral, user debt is increased.
    //
    // posted[user](wad) >= (debt[user](wad)) * amount (wad)) * collateralization (ray)
    //
    // us --- yDai ---> user
    // debt++
    function borrow(address to, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "Accounts: No mature borrow"
        );
        require(
            posted[to] >= (debtOf(to).add(yDai))
                .divd(_wethOracle.price())
                .muld(_collateralization, RAY),
            "Accounts: Post more collateral"
        );
        debt[to] = debt[to].add(yDai);
        _yDai.mint(to, yDai);
    }

    /// @dev Burns yDai from caller, user debt is decreased.
    function repay(uint256 yDai) public {
        repay(msg.sender, yDai);
    }
    
    /// @dev Burns yDai from `from` address, user debt is decreased.
    //                                                  debt_maturity
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_nominal
    //
    // user --- Dai ---> us
    // debt--
    function repay(address from, uint256 yDai) public {
        uint256 debtProportion = debt[from].mul(ray.unit())
            .divd(debtOf(from).mul(ray.unit()), RAY);
        _yDai.burn(from, yDai);
        debt[from] = debt[from].sub(yDai.muld(debtProportion, RAY)); // Will revert if not enough debt
    }
}