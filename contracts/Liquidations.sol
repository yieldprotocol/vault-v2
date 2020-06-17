pragma solidity ^0.6.2;

import "@openzeppelin/contracts/math/Math.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/ITreasury.sol";
import "./Constants.sol";


/// @dev The Liquidations contract for a Dealer allows to liquidate undercollateralized positions in a reverse Dutch auction.
contract Liquidations is Constants {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

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

    /// @dev Liquidates a position. The caller pays the debt of `from`, and `to` receives an amount of collateral.
    function liquidate(bytes32 collateral, address from, address to, uint256 daiAmount) public {
        require(
            auctions[collateral][from] > 0,
            "Liquidations: Vault is not in liquidation"
        );
        /* require(
            !_dealer.isCollateralized(collateral, from),
            "Liquidations: Vault is not undercollateralized"
        ); */ // Not checking for this, too expensive. Let the user stop the liquidations instead.
        require( // grab dai from liquidator and push to treasury
            _dai.transferFrom(from, address(_treasury), daiAmount),
            "Dealer: Dai transfer fail"
        );
        _treasury.pushDai();

        // calculate collateral to grab
        uint256 tokenAmount = daiAmount * price(collateral, from);
        // grab collateral from dealer
        _dealer.grab(collateral, from, daiAmount, tokenAmount);
    }

    /// @dev Return price of a collateral unit, in dai, at the present moment, for a given user
    // collateral = price * dai - TODO: Consider reversing so that it matches the Oracles
    // TODO: Optimize this for gas
    //                                             min(auction, elapsed)
    // dai * debt = token * posted * (2/3 + 1/3 * ----------------------)
    //                                                    auction
    //
    //                           9 * debt * auction
    // token = dai * ---------------------------------------------------------
    //                2 * posted * auction + 3 * debt * min(auction, elapsed)
    function price(bytes32 collateral, address user) public view returns (uint256) {
        require(
            auctions[collateral][user] > 0,
            "Liquidations: Vault is not targeted"
        );
        uint256 userDebt = _dealer.totalDebtDai(collateral, user);
        uint256 dividend = 9 * userDebt * auctionTime;
        uint256 divisor = (2 * _dealer.posted(collateral, user) * auctionTime) + (3 * userDebt * Math.min(auctionTime, (now - auctions[collateral][user])));
        return dividend / divisor;
    }
}