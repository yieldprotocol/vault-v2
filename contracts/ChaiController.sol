pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ILender.sol";
import "./interfaces/ISaver.sol";
import "./interfaces/IChai.sol";
import "./Constants.sol";
import "./YDai.sol"; // TODO: Find how to use an interface


/// @dev ChaiController manages a Chai/yDai series pair.
contract ChaiController is Ownable, Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;

    ILender internal _lender;
    ISaver internal _saver;
    IERC20 internal _dai;
    YDai internal _yDai;
    IChai internal _chai;
    IOracle internal _chaiOracle;

    mapping(address => uint256) internal posted; // In Chai
    mapping(address => uint256) internal debt; // In yDai

    uint256 public _stability; // accumulator (for stability fee) at maturity in RAY units
    uint256 public _collateralization; // accumulator (for stability fee) at maturity in RAY units

    constructor (
        address lender_,
        address saver_,
        address dai_,
        address yDai_,
        address chai_,
        address chaiOracle_,
        uint256 collateralization_
    ) public {
        _lender = ILender(lender_);
        _saver = ISaver(saver_);
        _dai = IERC20(dai_);
        _yDai = YDai(yDai_);
        _chai = IChai(chai_);
        _chaiOracle = IOracle(chaiOracle_);
        _collateralization = collateralization_;
    }

    /// @dev Collateral not in use for debt
    //
    //                       debtOf(user)(wad)
    // posted[user](wad) - -----------------------
    //                       daiOracle.get()(ray)
    //
    function unlockedOf(address user) public returns (uint256) {
        uint256 locked = debtOf(user)
            .divd(_chaiOracle.price(), RAY)
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
            return debt[user].muld(_yDai.rate(), RAY);
        }
        else {
            return debt[user];
        }
    }

    /// @dev Takes Chai as collateral from caller and gives it to the Lender (converted to Dai) if it has debt, or to the Saver otherwise
    // caller --- Chai ---> us
    function post(uint256 chai) public {
        post(msg.sender, chai);
    }

    /// @dev Takes Chai as collateral from `from` address and gives it to the Lender (converted to Dai) if it has debt, or to the Saver otherwise
    // from --- Chai ---> us
    function post(address from, uint256 chai) public {
        uint256 dai = chai.muld(_chaiOracle.price(), RAY);
        if (_lender.debt() > dai){
            _chai.transferFrom(from, address(this), chai);
            _chai.exit(from, chai);
            _lender.repay(address(this), dai);
        }
        else {
            _saver.join(from, chai);
        }
        posted[from] = posted[from].add(chai);
    }

    /// @dev Moves Chai collateral from Saver to caller if there are savings, or otherwise borrows Dai from Lender and sends it converted to Chai
    // us --- Chai ---> caller
    function withdraw(uint256 chai) public {
        withdraw(msg.sender, chai);
    }

    /// @dev Moves Chai collateral from Saver to `to` address if there are savings, or otherwise borrows Dai from Lender and sends it converted to Chai
    // us --- Chai ---> to
    function withdraw(address to, uint256 chai) public {
        require(
            unlockedOf(to) >= chai,
            "Accounts: Free more collateral"
        );
        posted[to] = posted[to].sub(chai); // Will revert if not enough posted
        if (_saver.savings() >= chai){
            _saver.exit(to, chai);
        }
        else {
            uint256 dai = chai.muld(_chaiOracle.price(), RAY);
            _lender.borrow(to, dai);
        }
    }

    // ---------- Manage Dai/yDai ----------
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
                .divd(_chaiOracle.price())
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
    // user --- yDai ---> us
    // debt--
    function repay(address from, uint256 yDai) public {
        uint256 debtProportion = debt[from].mul(RAY.unit())
            .divd(debtOf(from).mul(RAY.unit()), RAY);
        _yDai.burn(from, yDai);
        debt[from] = debt[from].sub(yDai.muld(debtProportion, RAY)); // Will revert if not enough debt
    }
}