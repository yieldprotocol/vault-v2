pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev Mint manages a Dai/yDai pair. Note that Dai is underlying, not collateral, and therefore the functions are minting and redeeming, instead of borrowing and repaying.
contract Mint is Constants {
    using DecimalMath for uint256;

    ITreasury internal _treasury;
    IERC20 internal _dai;
    IYDai internal _yDai;

    constructor (
        address treasury_,
        address dai_,
        address yDai_
    ) public {
        _treasury = ITreasury(treasury_);
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
        require(
            _dai.transferFrom(user, address(_treasury), dai), // Take dai from user and give it to Treasury
            "Mint: Dai transfer fail"
        );
        
        _treasury.pushDai();                                     // Have Treasury process the dai
        _yDai.mint(user, dai);                                // Mint yDai to user
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
        _treasury.pullDai(user, dai);                    // Give dai to user, from Treasury
    }
}