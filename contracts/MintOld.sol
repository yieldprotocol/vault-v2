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
import "@nomiclabs/buidler/console.sol";


/// @dev Mint manages a Dai/yDai pair. Note that Dai is underlying, not collateral, and therefore the functions are minting and redeeming, instead of borrowing and repaying.
contract MintOld is Ownable, Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;

    event Test(uint256 x);

    ILender internal _lender;
    ISaver internal _saver;
    IERC20 internal _dai;
    YDai internal _yDai;
    IChai internal _chai;
    IOracle internal _chaiOracle;

    constructor (
        address lender_,
        address saver_,
        address dai_,
        address yDai_,
        address chai_,
        address chaiOracle_
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
        require(
            _dai.transferFrom(user, address(this), dai),
            "Mint: DAI transfer fail"
        );
        /* if (_lender.debt() > dai){
            _lender.repay(address(this), dai);
        }
        else {
            uint256 chai = dai.divd(_chaiOracle.price(), RAY);
            _chai.join(address(this), chai);
            _saver.join(address(this), chai);
        } */
        console.log("Dai amount");
        console.log(dai);
        console.log("Dai balance");
        console.log(_dai.balanceOf(address(this)));
        _chai.approve(address(_dai), dai);
        _chai.join(address(this), dai);
        console.log("Chai amount");
        console.log(_chai.balanceOf(address(this)));
        // uint256 chai = dai.divd(_chaiOracle.price(), RAY);
        // _saver.join(address(this), chai);
        // _yDai.mint(user, dai);
    }

    /// @dev Burn yTokens and return an equal amount of underlying.
    // user --- yDai ---> us
    // us   --- Dai  ---> user
    function redeem(address user, uint256 yDai) public returns (bool) {
        require(
            _yDai.isMature(),
            "Mint: Only mature redeem"
        );
        _yDai.burn(user, yDai);
        uint256 chai = yDai.divd(_yDai.chi(), RAY);
        if (_saver.savings() > chai){
            _saver.exit(address(this), chai);
            _chai.exit(user, chai);
        }
        else {
            _lender.borrow(user, yDai);
        }
    }
}