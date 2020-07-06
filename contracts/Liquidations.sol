pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/ILiquidations.sol";
import "./interfaces/ITreasury.sol";
import "./helpers/Constants.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Liquidations contract for a Dealer allows to liquidate undercollateralized positions in a reverse Dutch auction.
contract Liquidations is ILiquidations, Orchestrated(), Constants, DecimalMath {
    using SafeMath for uint256;

    event Liquidation(bytes32 indexed collateral, address indexed user, uint256 started);

    IERC20 internal _dai;
    ITreasury internal _treasury;
    IDealer internal _dealer;

    uint256 public auctionTime;
    mapping(bytes32 => mapping(address => uint256)) public liquidations;

    bool public live = true;

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

    modifier onlyLive() {
        require(live == true, "Dealer: Not available during unwind");
        _;
    }

    /// @dev Disables buying at liquidations. To be called only when Treasury shuts down.
    function shutdown() public override {
        require(
            _treasury.live() == false,
            "Liquidations: Treasury is live"
        );
        live = false;
    }

    /// @dev Starts a liquidation process for a given collateral and user.
    function liquidate(bytes32 collateral, address user) public {
        require(
            liquidations[collateral][user] == 0,
            "Liquidations: Vault is already in liquidation"
        );
        require(
            !_dealer.isCollateralized(collateral, user),
            "Liquidations: Vault is not undercollateralized"
        );
        // solium-disable-next-line security/no-block-members
        liquidations[collateral][user] = now;
        emit Liquidation(collateral, user, liquidations[collateral][user]);
    }

    /// @dev Cancels a liquidation process
    function cancel(bytes32 collateral, address user) public {
        require(
            _dealer.isCollateralized(collateral, user),
            "Liquidations: Vault is undercollateralized"
        );
        // solium-disable-next-line security/no-block-members
        delete liquidations[collateral][user];
        emit Liquidation(collateral, user, liquidations[collateral][user]);
    }

    /// @dev Liquidates a position. The caller pays the debt of `from`, and `buyer` receives an amount of collateral.
    function buy(bytes32 collateral, address from, address buyer, uint256 daiAmount) public onlyLive {
        require(
            liquidations[collateral][from] > 0,
            "Liquidations: Vault is not in liquidation"
        );
        /* require(
            !_dealer.isCollateralized(collateral, from),
            "Liquidations: Vault is not undercollateralized"
        ); */ // Not checking for this, too expensive. Let the user stop the liquidations instead.
        _treasury.pushDai(buyer, daiAmount);

        // calculate collateral to grab. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        uint256 tokenAmount = divdrup(daiAmount, price(collateral, from));
        // grab collateral from dealer
        _dealer.grab(collateral, from, daiAmount, tokenAmount);

        if (collateral == WETH){
            _treasury.pullWeth(buyer, tokenAmount);
        } else if (collateral == CHAI) {
            _treasury.pullChai(buyer, tokenAmount);
        } else {
            revert("Dealer: Unsupported collateral");
        }
    }

    /// @dev Return price of a collateral unit, in dai, at the present moment, for a given user
    // dai = price * collateral
    // TODO: Optimize this for gas
    //
    //               posted      1      min(auction, elapsed)
    // price = 1 / (-------- * (--- + -----------------------))
    //                debt       2       2 * auction
    function price(bytes32 collateral, address user) public returns (uint256) {
        require(
            liquidations[collateral][user] > 0,
            "Liquidations: Vault is not targeted"
        );
        uint256 dividend1 = UNIT.mul(_dealer.posted(collateral, user));
        uint256 divisor1 = UNIT.mul(_dealer.totalDebtDai(collateral, user));
        uint256 dividend2 = UNIT.mul(1);
        uint256 divisor2 = UNIT.mul(2);
        uint256 dividend3 = UNIT.mul(Math.min(auctionTime, now - liquidations[collateral][user]));
        uint256 divisor3 = UNIT.mul(auctionTime.mul(2));
        uint256 term1 = divd(dividend1, divisor1);
        uint256 term2 = divd(dividend2, divisor2);
        uint256 term3 = divd(dividend3, divisor3);
        return divd(UNIT, muld(term1, term2.add(term3)));
    }
}