// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IController.sol";
import "./interfaces/ILiquidations.sol";
import "./interfaces/ITreasury.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Delegable.sol";
import "./helpers/Orchestrated.sol";
import "@nomiclabs/buidler/console.sol";


/**
 * @dev The Liquidations contract allows to liquidate undercollateralized weth vaults in a reverse Dutch auction.
 * Undercollateralized vaults can be liquidated by calling `liquidate`.
 * Collateral from vaults can be bought with Dai using `buy`.
 * Debt and collateral records will be adjusted in the Controller using `controller.grab`.
 * Dai taken in payment will be handed over to Treasury, and collateral assets bought will be taken from Treasury as well.
 * If a vault becomes colalteralized, the liquidation can be stopped with `cancel`.
 */
contract Liquidations is ILiquidations, Orchestrated(), Delegable(), DecimalMath {
    using SafeMath for uint256;

    event Liquidation(address indexed user, uint256 started, uint256 collateral, uint256 debt);

    bytes32 public constant WETH = "ETH-A";
    uint256 public constant AUCTION_TIME = 3600;
    uint256 public constant DUST = 25000000000000000; // 0.025 ETH
    uint256 public constant FEE = 25000000000000000; // 0.025 ETH

    IERC20 internal _dai;
    ITreasury internal _treasury;
    IController internal _controller;

    mapping(address => uint256) public liquidations;
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;

    bool public live = true;

    /// @dev The Liquidations constructor links it to the Dai, Treasury and Controller contracts.
    constructor (
        address dai_,
        address treasury_,
        address controller_
    ) public {
        _dai = IERC20(dai_);
        _treasury = ITreasury(treasury_);
        _controller = IController(controller_);
    }

    /// @dev Only while Liquidations is not unwinding due to a MakerDAO shutdown.
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


    /// @dev Return if the debt of an user is between zero and the dust level
    /// @param user Address of the user vault
    function aboveDustOrZero(address user) public view returns (bool) {
        return collateral[user] == 0 || DUST < collateral[user];
    }

    /// @dev Starts a liquidation process for an undercollateralized vault.
    /// A liquidation fee is transferred from the liquidated user to a designated account as payment.
    /// @param user Address of the user vault to liquidate.
    /// @param to Address of the liquidations account to receive the liquidation fee.
    function liquidate(address user, address to) public {
        require(
            liquidations[user] == 0,
            "Liquidations: Vault is already in liquidation"
        );
        require(
            !_controller.isCollateralized(WETH, user),
            "Liquidations: Vault is not undercollateralized"
        );
        // solium-disable-next-line security/no-block-members
        liquidations[user] = now;

        (uint256 userCollateral, uint256 userDebt) = _controller.erase(WETH, user);
        collateral[user] = userCollateral.sub(FEE);
        collateral[to] = collateral[to].add(FEE);
        debt[user] = userDebt;

        emit Liquidation(user, liquidations[user], userCollateral, userDebt);
    }

    /// @dev Buy a portion of a position under liquidation.
    /// The caller pays the debt of `user`, and `buyer` receives an amount of collateral.
    /// `buyer` can delegate to other addresses to buy for him. Also needs to use `ERC20.approve`.
    /// @param user Address of the user vault to liquidate.
    /// @param buyer Address of the wallet paying Dai for liquidated collateral.
    /// @param daiAmount Amount of Dai to give in exchange for liquidated collateral.
    /// @return The amount of collateral obtained.
    function buy(address buyer, address user, uint256 daiAmount) // TODO: make Address parameters be `from`, `to` and `vault`
        public onlyLive
        onlyHolderOrDelegate(buyer, "Controller: Only Holder Or Delegate")
        returns (uint256)
    {
        require(
            debt[user] > 0,
            "Liquidations: Vault is not in liquidation"
        );
        _treasury.pushDai(buyer, daiAmount);

        // calculate collateral to grab. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        uint256 tokenAmount = divdrup(daiAmount, price(user));

        collateral[user] = collateral[user].sub(tokenAmount);
        debt[user] = debt[user].sub(daiAmount);

        _treasury.pullWeth(buyer, tokenAmount);

        require(
            aboveDustOrZero(user),
            "Liquidations: Below dust"
        );

        // TODO: return tokenAmount
    }

    /// @dev Retrieve weth from a liquidations account. This weth could come from liquidator fees or as remainders of liquidations.
    /// `from` can delegate to other addresses to withdraw from him.
    /// @param from Address of the liquidations user vault to withdraw weth from.
    /// @param to Address of the wallet receiving the withdrawn weth.
    /// @param tokenAmount Amount of Weth to withdraw.
    function withdraw(address from, address to, uint256 tokenAmount)
        public onlyLive
        onlyHolderOrDelegate(from, "Controller: Only Holder Or Delegate")
    {
        require(
            debt[from] == 0,
            "Liquidations: User still in liquidation"
        );

        collateral[from] = collateral[from].sub(tokenAmount);

        _treasury.pullWeth(to, tokenAmount);
    }


    /// @dev Return price of a collateral unit, in dai, at the present moment, for a given user
    /// @param user Address of the user vault in liquidation.
    // dai = price * collateral
    //
    //                collateral      1      min(auction, elapsed)
    // price = 1 / (------------- * (--- + -----------------------))
    //                   debt         2       2 * auction
    function price(address user) public view returns (uint256) {
        require(
            liquidations[user] > 0,
            "Liquidations: Vault is not targeted"
        );
        uint256 dividend1 = collateral[user];
        uint256 divisor1 = debt[user];
        uint256 term1 = dividend1.mul(UNIT).div(divisor1);
        uint256 dividend3 = Math.min(AUCTION_TIME, now.sub(liquidations[user]));
        uint256 divisor3 = AUCTION_TIME.mul(2);
        uint256 term2 = UNIT.div(2);
        uint256 term3 = dividend3.mul(UNIT).div(divisor3);
        return divd(UNIT, muld(term1, term2.add(term3)));
    }
}
