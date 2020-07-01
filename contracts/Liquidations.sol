pragma solidity ^0.6.2;

import "./helpers/Orchestrated.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/ILiquidations.sol";
import "./interfaces/ITreasury.sol";
import "./helpers/Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev The Liquidations contract for a Dealer allows to liquidate undercollateralized positions in a reverse Dutch auction.
contract Liquidations is ILiquidations, Orchestrated(), Constants {
    using DecimalMath for uint256;
    using DecimalMath for uint8;
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
        require( // grab dai from buyer and push to treasury
            _dai.transferFrom(buyer, address(_treasury), daiAmount),
            "Dealer: Dai transfer fail"
        );
        _treasury.pushDai();

        // calculate collateral to grab. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        uint256 tokenAmount = divdrup(daiAmount, price(collateral, from), RAY);
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
        uint256 dividend1 = RAY.unit().mul(_dealer.posted(collateral, user));
        uint256 divisor1 = RAY.unit().mul(_dealer.totalDebtDai(collateral, user));
        uint256 dividend2 = RAY.unit().mul(1);
        uint256 divisor2 = RAY.unit().mul(2);
        uint256 dividend3 = RAY.unit().muld(Math.min(auctionTime, now - liquidations[collateral][user]), RAY);
        uint256 divisor3 = RAY.unit().muld(auctionTime, RAY).mul(2);
        uint256 term1 = dividend1.divd(divisor1, RAY);
        uint256 term2 = dividend2.divd(divisor2, RAY);
        uint256 term3 = dividend3.divd(divisor3, RAY);
        return RAY.unit().divd(term1.muld(term2.add(term3), RAY), RAY);
    }

    /// @dev Divides x between y, rounding up to the closest representable number.
    /// Assumes x and y are both fixed point with `decimals` digits.
     // TODO: Check if this needs to be taken from DecimalMath.sol
    function divdrup(uint256 x, uint256 y, uint8 decimals)
        internal pure returns (uint256)
    {
        uint256 z = x.mul((decimals + 1).unit()).div(y);
        if (z % 10 > 0) return z / 10 + 1;
        else return z / 10;
    }
}