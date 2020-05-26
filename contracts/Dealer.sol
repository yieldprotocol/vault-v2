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
    mapping(address => mapping(bytes32 => uint256)) internal posted;     // In Weth or Chai, per collateral type
    mapping(address => mapping(bytes32 => uint256)) internal debtYDai;   // In yDai, per collateral type

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
    function powerOf(address user, bytes32 collateral) public returns (uint256) {
        // collateral = dai * price
        return posted[user][collateral].divd(oracles[collateral].price(), RAY);
    }

    /// @dev Return debt in dai of an user
    //
    //                        rate_now
    // debt_now = debt_mat * ----------
    //                        rate_mat
    //
    function debtDai(address user, bytes32 collateral) public view returns (uint256) {
        return inDai(debtYDai[user][collateral]);
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
    function post(address from, bytes32 collateral, uint256 amount) public virtual {
        if (collateral == WETH){
            require(
                tokens[collateral].transferFrom(from, address(_treasury), amount),
                "Dealer: Collateral transfer fail"
            );
            _treasury.post();                          // Have Treasury process the weth
        } else if (collateral == CHAI) {
            postChai(from, amount);
        } else {
            revert("Dealer: Unsupported collateral");
        }
        posted[from][collateral] = posted[from][collateral].add(amount);
    }

    /// @dev Takes chai from `from` address, unwraps it to dai, and gives it to the Treasury
    // from --- Chai -> Dai ---> treasury
    function postChai(address from, uint256 chai) internal { // TODO: Have Treasury wrap and unwrap
        bytes32 collateral = CHAI;
        require(
            tokens[collateral].transferFrom(from, address(this), chai),
            "Dealer: Collateral transfer fail"
        );                           // Grab chai and update posted
        uint256 dai = chai.divd(oracles[collateral].price(), RAY);   // dai = chai / price
        IChai(address(tokens[collateral])).draw(address(this), dai); // Grab dai from Chai, converted from chai
        _dai.transfer(address(_treasury), dai);                      // Give Treasury the dai
        _treasury.push();                                            // Have Treasury process the dai
    }

    /// @dev Returns collateral to `to` address
    // us --- Token ---> to
    function withdraw(address to, bytes32 collateral, uint256 amount) public virtual {
        require( // Is this needed for Chai?
            powerOf(to, collateral) >= debtDai(to, collateral),
            "Dealer: Undercollateralized"
        );
        require( // (power - debt) * price
            (powerOf(to, collateral) - debtDai(to, collateral)).muld(oracles[collateral].price(), RAY) >= amount, // SafeMath not needed
            "Dealer: Free more collateral"
        );
        posted[to][collateral] = posted[to][collateral].sub(amount); // Will revert if not enough posted
        if (collateral == WETH){
            _treasury.withdraw(to, amount);                          // Take weth from Treasury and give it to `to`
        } else if (collateral == CHAI) {
            withdrawChai(to, amount);
        } else {
            revert("Dealer: Unsupported collateral");
        }
    }

    /// @dev Takes dai from Treasury, wraps it to chai, and gives it to `to` address
    // Treasury --- Dai -> Chai ---> to
    function withdrawChai(address to, uint256 chai) internal {
        bytes32 collateral = CHAI;
        uint256 dai = chai.divd(oracles[collateral].price(), RAY);   // dai = chai / price
        _treasury.pull(address(this), dai);                          // Take dai from treasury
        _dai.approve(address(tokens[collateral]), dai);              // Chai will take dai
        IChai(address(tokens[collateral])).join(address(this), dai); // Give dai to Chai, take chai back
        require(
            tokens[collateral].transfer(to, chai),                   //  Transfer collateral to `to`
            "Dealer: Collateral transfer fail"
        );
    }

    /// @dev Returns collateral to `to` address, converted to Dai
    // us --- Dai ---> to
    function withdrawDai(address to, bytes32 collateral, uint256 dai) public virtual {
        require( // Is this needed for Chai?
            powerOf(to, collateral) >= debtDai(to, collateral),
            "Dealer: Undercollateralized"
        );
        uint256 amount = dai.muld(oracles[collateral].price(), RAY);  // collateral = dai * price
        require( // (power - debt) * price
            (powerOf(to, collateral) - debtDai(to, collateral)).muld(oracles[collateral].price(), RAY) >= amount, // SafeMath not needed
            "Dealer: Free more collateral"
        );
        posted[to][collateral] = posted[to][collateral].sub(amount); // Will revert if not enough posted
        if (collateral == WETH || collateral == CHAI){
            _treasury.pull(to, dai);                           // Take dai from treasury and give it to `to`
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
    function borrow(address to, bytes32 collateral, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "Dealer: No mature borrow"
        );
        require( // collateral = dai * price
            posted[to][collateral] >= (debtDai(to, collateral).add(yDai))
                .muld(oracles[collateral].price(), RAY),
            "Dealer: Post more collateral"
        );
        debtYDai[to][collateral] = debtYDai[to][collateral].add(yDai);
        _yDai.mint(to, yDai);
    }

    /// @dev Burns yDai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- yDai ---> us
    // debt--
    function restore(address from, bytes32 collateral, uint256 yDai) public {
        (uint256 toRepay, uint256 debtDecrease) = amounts(from, collateral, yDai);
        _yDai.burn(from, toRepay);
        debtYDai[from][collateral] = debtYDai[from][collateral].sub(debtDecrease);
    }

    /// @dev Takes dai from `from` address, user debt is decreased.
    //                                                  debt_nominal
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_now
    //
    // user --- dai ---> us
    // debt--
    function repay(address from, bytes32 collateral, uint256 dai) public {
        require(
            _dai.transferFrom(from, address(_treasury), dai),  // Take dai from user to Treasury
            "Dealer: Dai transfer fail"
        );

        _treasury.push();                                      // Have Treasury process the dai
        (uint256 toRepay, uint256 debtDecrease) = amounts(from, collateral, inYDai(dai));
        debtYDai[from][collateral] = debtYDai[from][collateral].sub(debtDecrease);
    }

    /// @dev Calculates the amount to repay and the amount by which to reduce the debt
    function amounts(address user, bytes32 collateral, uint256 yDai) internal view returns(uint256, uint256) {
        uint256 toRepay = Math.min(yDai, debtDai(user, collateral));
        uint256 debtProportion = debtYDai[user][collateral].mul(RAY.unit())
            .divd(debtDai(user, collateral).mul(RAY.unit()), RAY);
        return (toRepay, toRepay.muld(debtProportion, RAY));
    }
}