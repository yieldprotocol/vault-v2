pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILender.sol";
import "./interfaces/ISaver.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IChai.sol";
import "./Constants.sol";
import "./YDai.sol";


/// @dev YdaiController manages a Dai/yDai pair. Note that Dai is underlying, not collateral, and therefore the functions are minting and redeeming, instead of borrowing and repaying.
contract YDaiController is IController, Ownable, Constants {
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

    constructor (
        address lender_,
        address saver_,
        address _dai,
        address yDai_,
        address chai_,
        address chaiOracle_,
    ) public {
        _lender = ILender(lender_);
        _saver = ISaver(saver_);
        _dai = IERC20(dai_);
        _yDai = YDai(yDai_);
        _chai = IChai(chai_);
        _chaiOracle = IOracle(chaiOracle_);
    }

    /// @dev Mint yTokens by posting an equal amount of Dai.
    // user --- Dai  ---> us
    // us   --- yDai ---> user
    function mint(address user, uint256 dai) public {
        if (_lender.debt() > dai){
            _lender.repay(user, dai);
        }
        else {
            _dai.transferFrom(user, address(this), dai);
            uint256 chai = dai.divd(_chaiOracle.price(), RAY);
            _saver.join(chai);
        }
        _yDai.mint(user, dai);
    }

    /// @dev Burn yTokens and return an equal amount of underlying.
    // user --- yDai ---> us
    // us   --- Dai  ---> user
    function redeem(address user, uint256 ydai) public returns (bool) {
        require(
            _yDai.isMature(),
            "Accounts: Only mature redeem"
        );
        _yDai.burn(user, ydai);
        uint256 chai = ydai.divd(yDai.chi(), RAY);
        if (_saver.savings() > chai){
            _saver.exit(chai);
            _chai.exit(user, chai);
        }
        else {
            _lender.borrow(user, ydai);
        }
    }
}