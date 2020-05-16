pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILender.sol";
import "./interfaces/ISaver.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev Mint manages a Dai/yDai pair. Note that Dai is underlying, not collateral, and therefore the functions are minting and redeeming, instead of borrowing and repaying.
contract Mint is Constants {
    using DecimalMath for uint256;

    ILender internal _lender;
    ISaver internal _saver;
    IERC20 internal _dai;
    IYDai internal _yDai;

    constructor (
        address lender_,
        address saver_,
        address dai_,
        address yDai_
    ) public {
        _lender = ILender(lender_);
        _saver = ISaver(saver_);
        _dai = IERC20(dai_);
        _yDai = IYDai(yDai_);
    }

    /// @dev Mint yDai by posting an equal amount of Dai.
    /// If the Lender has debt it is paid, otherwise the dai is converted into chai
    // user --- Dai  ---> us
    // us   --- yDai ---> user
    function mint(address user, uint256 dai) public {
        require(
            !_yDai.isMature(),
            "Mint: yDai is mature"
        );
        _dai.transferFrom(user, address(this), dai); // Get the dai from user

        uint256 toRepay = Math.min(_lender.debt(), dai);
        _dai.approve(address(_lender), toRepay);     // Lender will take the dai
        _lender.repay(address(this), toRepay);       // Lender takes dai from Mint to repay debt

        uint256 toSave = dai - toRepay;             // toRepay can't be greater than dai
        _dai.approve(address(_saver), toSave);      // Saver will take dai
        _saver.hold(address(this), toSave);         // Send dai to Saver

        _yDai.mint(user, dai);                       // Mint yDai to user
    }

    /// @dev Burn yTokens and return an equal amount of underlying.
    /// If the Saver has savings they are used to deliver the dai to the user, otherwise dai is borrowed from MakerDao
    // user --- yDai ---> us
    // us   --- Dai  ---> user
    function redeem(address user, uint256 yDai) public {
        require(
            _yDai.isMature(),
            "Mint: yDai is not mature"
        );
        _yDai.burn(user, yDai);                       // Burn yDai from user
        uint256 dai = yDai.muld(_yDai.chi(), RAY);    // User gets interest for holding after maturity

        uint256 toRelease = Math.min(_saver.savings(), dai);
        _saver.release(user, toRelease);                // Give dai to user, from Saver

        uint256 toBorrow = dai - toRelease;           // toRelease can't be greater than dai
        _lender.borrow(user, toBorrow);                // Borrow Dai from Lender to user
    }
}