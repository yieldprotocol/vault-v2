pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IController.sol";
import "./interfaces/ILiquidations.sol";
import "./interfaces/ITreasury.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Liquidations contract for a Controller allows to liquidate undercollateralized positions in a reverse Dutch auction.
contract Liquidations is ILiquidations, Orchestrated(), DecimalMath {
    using SafeMath for uint256;

    event Liquidation(bytes32 indexed collateral, address indexed user, uint256 started);

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IERC20 internal _dai;
    ITreasury internal _treasury;
    IController internal _controller;

    uint256 public auctionTime;
    mapping(bytes32 => mapping(address => uint256)) public liquidations;

    bool public live = true;

    constructor (
        address dai_,
        address treasury_,
        address controller_,
        uint256 auctionTime_
    ) public {
        _dai = IERC20(dai_);
        _treasury = ITreasury(treasury_);
        _controller = IController(controller_);

        require(
            auctionTime_ > 0,
            "Liquidations: Auction time is zero"
        );
        auctionTime = auctionTime_;
    }

    modifier onlyLive() {
        require(live == true, "Controller: Not available during unwind");
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
            !_controller.isCollateralized(collateral, user),
            "Liquidations: Vault is not undercollateralized"
        );
        // solium-disable-next-line security/no-block-members
        liquidations[collateral][user] = now;
        emit Liquidation(collateral, user, liquidations[collateral][user]);
    }

    /// @dev Cancels a liquidation process
    function cancel(bytes32 collateral, address user) public {
        require(
            _controller.isCollateralized(collateral, user),
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
            !_controller.isCollateralized(collateral, from),
            "Liquidations: Vault is not undercollateralized"
        ); */ // Not checking for this, too expensive. Let the user stop the liquidations instead.
        _treasury.pushDai(buyer, daiAmount);

        // calculate collateral to grab. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        uint256 tokenAmount = divdrup(daiAmount, price(collateral, from));
        // grab collateral from controller
        _controller.grab(collateral, from, daiAmount, tokenAmount);

        if (collateral == WETH){
            _treasury.pullWeth(buyer, tokenAmount);
        } else if (collateral == CHAI) {
            _treasury.pullChai(buyer, tokenAmount);
        } else {
            revert("Controller: Unsupported collateral");
        }
    }

    /// @dev Return price of a collateral unit, in dai, at the present moment, for a given user
    // dai = price * collateral
    //
    //               posted      1      min(auction, elapsed)
    // price = 1 / (-------- * (--- + -----------------------))
    //                debt       2       2 * auction
    function price(bytes32 collateral, address user) public returns (uint256) {
        require(
            liquidations[collateral][user] > 0,
            "Liquidations: Vault is not targeted"
        );
        uint256 dividend1 = _controller.posted(collateral, user);
        uint256 divisor1 = _controller.totalDebtDai(collateral, user);
        uint256 term1 = dividend1.mul(UNIT).div(divisor1);
        uint256 dividend3 = Math.min(auctionTime, now - liquidations[collateral][user]);
        uint256 divisor3 = auctionTime.mul(2);
        uint256 term2 = UNIT.div(2);
        uint256 term3 = dividend3.mul(UNIT).div(divisor3);
        return divd(UNIT, muld(term1, term2.add(term3)));
    }
}