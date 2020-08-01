// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IEnd.sol";
import "./interfaces/IChai.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IController.sol";
import "./interfaces/IYDai.sol";
import "./interfaces/ILiquidations.sol";
import "./helpers/DecimalMath.sol";



/**
 * @dev Unwind allows everyone to recover their assets from the Yield protocol in the event of a MakerDAO shutdown.
 * During the unwind process, the system debt to MakerDAO is settled first with `settleTreasury`, extracting all free weth.
 * Once the Treasury is settled, any system savings are converted from Chai to Weth using `cashSavings`.
 * At this point, users can settle their positions using `settle`. The MakerDAO rates will be used to convert all debt and collateral to a Weth payout.
 * Users can also redeem here their yDai for a Weth payout, using `redeem`.
 */
contract Unwind is Ownable(), DecimalMath {
    using SafeMath for uint256;

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IDaiJoin internal _daiJoin;
    IERC20 internal _weth;
    IGemJoin internal _wethJoin;
    IPot internal _pot;
    IEnd internal _end;
    IChai internal _chai;
    ITreasury internal _treasury;
    IController internal _controller;
    ILiquidations internal _liquidations;

    uint256 public _fix; // Dai to weth price on DSS Unwind
    uint256 public _chi; // Chai to dai price on DSS Unwind

    uint256 internal _treasuryWeth; // Weth that was held by treasury before settling

    bool public settled;
    bool public cashedOut;
    bool public live = true;

    /// @dev The constructor links to vat, daiJoin, weth, wethJoin, jug, pot, end, chai, treasury, controller and liquidations.
    /// Liquidations should have privileged access to treasury, controller and liquidations using orchestration.
    /// The constructor gives treasury and end permission on unwind's MakerDAO vaults.
    constructor (
        address vat_,
        address daiJoin_,
        address weth_,
        address wethJoin_,
        address pot_,
        address end_,
        address chai_,
        address treasury_,
        address controller_,
        address liquidations_
    ) public {
        // These could be hardcoded for mainnet deployment.
        _vat = IVat(vat_);
        _daiJoin = IDaiJoin(daiJoin_);
        _weth = IERC20(weth_);
        _wethJoin = IGemJoin(wethJoin_);
        _pot = IPot(pot_);
        _end = IEnd(end_);
        _chai = IChai(chai_);
        _treasury = ITreasury(treasury_);
        _controller = IController(controller_);
        _liquidations = ILiquidations(liquidations_);

        _vat.hope(address(_treasury));
        _vat.hope(address(_end));
    }

    /// @dev max(0, x - y)
    function subFloorZero(uint256 x, uint256 y) public pure returns(uint256) {
        if (y >= x) return 0;
        else return x - y;
    }

    /// @dev Safe casting from uint256 to int256
    function toInt(uint256 x) internal pure returns(int256) {
        require(
            x <= 57896044618658097711785492504343953926634992332820282019728792003956564819967,
            "Treasury: Cast overflow"
        );
        return int256(x);
    }

    /// @dev Disables treasury, controller and liquidations.
    function unwind() public {
        require(
            _end.tag(WETH) != 0,
            "Unwind: MakerDAO not shutting down"
        );
        live = false;
        _treasury.shutdown();
        _controller.shutdown();
        _liquidations.shutdown();
    }

    /// @dev Return the Dai equivalent value to a Chai amount.
    /// @param chaiAmount The Chai value to convert.
    /// @param chi The `chi` value from `Pot`.
    function chaiToDai(uint256 chaiAmount, uint256 chi) public pure returns(uint256) {
        return muld(chaiAmount, chi);
    }

    /// @dev Return the Weth equivalent value to a Dai amount, during Dss Shutdown
    /// @param daiAmount The Dai value to convert.
    /// @param fix The `fix` value from `End`.
    function daiToFixWeth(uint256 daiAmount, uint256 fix) public pure returns(uint256) {
        return muld(daiAmount, fix);
    }

    /// @dev Settle system debt in MakerDAO and free remaining collateral.
    function settleTreasury() public {
        require(
            live == false,
            "Unwind: Unwind first"
        );
        (uint256 ink, uint256 art) = _vat.urns(WETH, address(_treasury));
        _treasuryWeth = ink;                            // We will need this to skim profits
        _vat.fork(                                      // Take the treasury vault
            WETH,
            address(_treasury),
            address(this),
            toInt(ink),
            toInt(art)
        );
        _end.skim(WETH, address(this));                // Settle debts
        _end.free(WETH);                               // Free collateral
        uint256 gem = _vat.gem(WETH, address(this));   // Find out how much collateral we have now
        _wethJoin.exit(address(this), gem);            // Take collateral out
        settled = true;
    }

    /// @dev Put all chai savings in MakerDAO and exchange them for weth
    function cashSavings() public {
        require(
            _end.tag(WETH) != 0,
            "Unwind: End.sol not caged"
        );
        require(
            _end.fix(WETH) != 0,
            "Unwind: End.sol not ready"
        );
        uint256 daiTokens = _chai.dai(address(_treasury));   // Find out how much is the chai worth
        _chai.draw(address(_treasury), _treasury.savings()); // Get the chai as dai
        _daiJoin.join(address(this), daiTokens);             // Put the dai into MakerDAO
        _end.pack(daiTokens);                                // Into End.sol, more exactly
        _end.cash(WETH, daiTokens);                          // Exchange the dai for weth
        uint256 gem = _vat.gem(WETH, address(this));         // Find out how much collateral we have now
        _wethJoin.exit(address(this), gem);                  // Take collateral out
        cashedOut = true;

        _fix = _end.fix(WETH);
        _chi = _pot.chi();
    }

    /// @dev Settles a series position in Controller for any user, and then returns any remaining collateral as weth using the unwind Dai to Weth price.
    /// @param collateral Valid collateral type.
    /// @param user User vault to settle, and wallet to receive the corresponding weth.
    function settle(bytes32 collateral, address user) public {
        require(settled && cashedOut, "Unwind: Not ready");

        (uint256 tokens, uint256 debt) = _controller.erase(collateral, user);

        uint256 remainder;
        if (collateral == WETH) {
            remainder = subFloorZero(tokens, daiToFixWeth(debt, _fix));
        } else if (collateral == CHAI) {
            remainder = daiToFixWeth(subFloorZero(chaiToDai(tokens, _chi), debt), _fix);
        }
        require(_weth.transfer(user, remainder));
    }

    /// @dev Settles a user vault in Liquidations, and then returns any remaining collateral as weth using the unwind Dai to Weth price.
    /// @param user User vault to settle, and wallet to receive the corresponding weth.
    function settleLiquidations(address user) public {
        require(settled && cashedOut, "Unwind: Not ready");

        (uint256 weth, uint256 debt) = _liquidations.erase(user);
        uint256 remainder = subFloorZero(weth, daiToFixWeth(debt, _fix));

        require(_weth.transfer(user, remainder));
    }

    /// @dev Redeems YDai for weth for any user. YDai.redeem won't work if MakerDAO is in shutdown.
    /// @param maturity Maturity of an added series
    /// @param user Wallet containing the yDai to burn.
    function redeem(uint256 maturity, address user) public {
        require(settled && cashedOut, "Unwind: Not ready");
        IYDai yDai = _controller.series(maturity);
        uint256 yDaiAmount = yDai.balanceOf(user);
        yDai.burn(user, yDaiAmount);
        require(
            _weth.transfer(
                user,
                daiToFixWeth(muld(yDaiAmount, yDai.chiGrowth()), _fix)
            )
        );
    }
}
