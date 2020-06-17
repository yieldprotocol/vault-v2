pragma solidity ^0.6.2;

import "@openzeppelin/contracts/math/Math.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/ITreasury.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Liquidations contract for a Dealer allows to liquidate undercollateralized positions in a reverse Dutch auction.
contract Liquidations is Constants {
    using DecimalMath for uint256;
    using DecimalMath for uint8;
    using SafeMath for uint256;

    IERC20 internal _dai;
    ITreasury internal _treasury;
    IDealer internal _dealer;

    uint256 public auctionTime;

    mapping(bytes32 => mapping(address => uint256)) public auctions;

    constructor (
        address dai_,
        address treasury_,
        address dealer_,
        uint256 auctionTime_
    ) public {
        _dai = IERC20(dai_);
        _treasury = ITreasury(treasury_);
        _dealer = IDealer(dealer_);

        require(
            auctionTime_ > 0,
            "Liquidations: Auction time is zero"
        );
        auctionTime = auctionTime_;
    }

    /// @dev Starts a liquidation process for a given collateral and user.
    function start(bytes32 collateral, address user) public {
        require(
            auctions[collateral][user] == 0,
            "Liquidations: Vault is already in liquidation"
        );
        require(
            !_dealer.isCollateralized(collateral, user),
            "Liquidations: Vault is not undercollateralized"
        );
        // solium-disable-next-line security/no-block-members
        auctions[collateral][user] = now;
    }

    /// @dev Cancels a liquidation process
    function cancel(bytes32 collateral, address user) public {
        require(
            _dealer.isCollateralized(collateral, user),
            "Liquidations: Vault is undercollateralized"
        );
        // solium-disable-next-line security/no-block-members
        delete auctions[collateral][user];
    }

    /// @dev Liquidates a position. The caller pays the debt of `from`, and `liquidator` receives an amount of collateral.
    function liquidate(bytes32 collateral, address from, address liquidator, uint256 daiAmount) public {
        require(
            auctions[collateral][from] > 0,
            "Liquidations: Vault is not in liquidation"
        );
        /* require(
            !_dealer.isCollateralized(collateral, from),
            "Liquidations: Vault is not undercollateralized"
        ); */ // Not checking for this, too expensive. Let the user stop the liquidations instead.
        require( // grab dai from liquidator and push to treasury
            _dai.transferFrom(liquidator, address(_treasury), daiAmount),
            "Dealer: Dai transfer fail"
        );
        _treasury.pushDai();

        // calculate collateral to grab
        uint256 tokenAmount = daiAmount.muld(price(collateral, from), RAY);
        // grab collateral from dealer
        _dealer.grab(collateral, from, daiAmount, tokenAmount);

        if (collateral == WETH){
            _treasury.pullWeth(liquidator, tokenAmount);                          // Have Treasury process the weth
        } else if (collateral == CHAI) {
            _treasury.pullChai(liquidator, tokenAmount);
        } else {
            revert("Dealer: Unsupported collateral");
        }
    }

    /// @dev Return price of a collateral unit, in dai, at the present moment, for a given user
    // collateral = price * dai - TODO: Consider reversing so that it matches the Oracles
    // TODO: Optimize this for gas
    //
    //                posted      2      min(auction, elapsed)
    // token = dai * -------- * (--- + -----------------------)
    //                 debt       3       3 * auction
    function price(bytes32 collateral, address user) public view returns (uint256) {
        require(
            auctions[collateral][user] > 0,
            "Liquidations: Vault is not targeted"
        );
        uint256 dividend1 = RAY.unit().mul(_dealer.posted(collateral, user));
        uint256 divisor1 = RAY.unit().mul(_dealer.totalDebtDai(collateral, user));
        uint256 dividend2 = RAY.unit().mul(2);
        uint256 divisor2 = RAY.unit().mul(3);
        uint256 dividend3 = RAY.unit().muld(Math.min(auctionTime, now - auctions[collateral][user]), RAY);
        uint256 divisor3 = RAY.unit().muld(auctionTime, RAY).mul(3);
        uint256 term1 = dividend1.divd(divisor1, RAY);
        uint256 term2 = dividend2.divd(divisor2, RAY);
        uint256 term3 = dividend3.divd(divisor3, RAY);
        return term1.muld(term2.add(term3), RAY); // TODO: Might want to round up in the three previous terms
    }
}