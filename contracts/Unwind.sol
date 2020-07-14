pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
import "./interfaces/IJug.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IEnd.sol";
import "./interfaces/IChai.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IController.sol";
import "./interfaces/IYDai.sol";
import "./interfaces/ILiquidations.sol";
import "./helpers/DecimalMath.sol";
// import "@nomiclabs/buidler/console.sol";


/// @dev Treasury manages the Dai, interacting with MakerDAO's vat and chai when needed.
contract Unwind is Ownable(), DecimalMath {
    using SafeCast for uint256;
    using SafeMath for uint256;


    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IDaiJoin internal _daiJoin;
    IERC20 internal _weth;
    IGemJoin internal _wethJoin;
    IJug internal _jug;
    IPot internal _pot;
    IEnd internal _end;
    IChai internal _chai;
    ITreasury internal _treasury;
    IController internal _controller;
    ILiquidations internal _liquidations;

    // TODO: Series related code is repeated with Controller, can be extracted into a parent class.
    mapping(uint256 => IYDai) public series; // YDai series, indexed by maturity
    uint256[] internal seriesIterator;       // We need to know all the series

    uint256 public _fix; // Dai to weth price on DSS Unwind
    uint256 public _chi; // Chai to dai price on DSS Unwind

    bool public settled;
    bool public cashedOut;
    bool public live = true;

    constructor (
        address vat_,
        address daiJoin_,
        address weth_,
        address wethJoin_,
        address jug_,
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
        _jug = IJug(jug_);
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

    /// @dev Returns if a series has been added to the Controller, for a given series identified by maturity
    function containsSeries(uint256 maturity) public view returns (bool) {
        return address(series[maturity]) != address(0);
    }

    /// @dev Adds an yDai series to this Controller
    function addSeries(address yDaiContract) public onlyOwner {
        uint256 maturity = IYDai(yDaiContract).maturity();
        require(
            !containsSeries(maturity),
            "Controller: Series already added"
        );
        series[maturity] = IYDai(yDaiContract);
        seriesIterator.push(maturity);
    }

    /// @dev Disables treasury and controller.
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

    function getChi() public returns (uint256) {
        return (now > _pot.rho()) ? _pot.drip() : _pot.chi();
    }

    function getRate() public returns (uint256) {
        uint256 rate;
        (, uint256 rho) = _jug.ilks(WETH);
        if (now > rho) {
            rate = _jug.drip(WETH);
        } else {
            (, rate,,,) = _vat.ilks(WETH);
        }
        return rate;
    }

    /// @dev Calculates how much profit is in the system and transfers it to the beneficiary
    function skimWhileLive(address beneficiary) public { // TODO: Hardcode
        require(
            live == true, // If DSS is not live this method will fail later on.
            "Unwind: Can only skimWhileLive if live"
        );

        uint256 profit = _chai.balanceOf(address(_treasury));
        profit = profit.add(_yDaiProfit(getChi(), getRate()));
        profit = profit.sub(divd(_treasury.debt(), getChi()));
        profit = profit.sub(_controller.systemPosted(CHAI));

        _treasury.pullChai(beneficiary, profit);
    }

    /// @dev Calculates how much profit is in the system and transfers it to the beneficiary
    function skimDssShutdown(address beneficiary) public { // TODO: Hardcode
        require(settled && cashedOut, "Unwind: Not ready");

        uint256 chi = _pot.chi();
        (, uint256 rate,,,) = _vat.ilks(WETH);
        uint256 profit = _weth.balanceOf(address(this));

        profit = profit.add(muld(muld(_yDaiProfit(chi, rate), _fix), chi));
        profit = profit.sub(_controller.systemPosted(WETH));
        profit = profit.sub(muld(muld(_controller.systemPosted(CHAI), _fix), chi));

        _weth.transfer(beneficiary, profit);
    }

    /// @dev Returns the profit accummulated in the system due to yDai supply and debt, in chai, for a given chi and rate.
    function _yDaiProfit(uint256 chi, uint256 rate) internal returns (uint256) {
        uint256 profit;

        for (uint256 i = 0; i < seriesIterator.length; i += 1) {
            uint256 maturity = seriesIterator[i];
            IYDai yDai = IYDai(series[seriesIterator[i]]);

            uint256 chi0;
            uint256 rate0;
            if (yDai.isMature()){
                chi0 = yDai.chi0();
                rate0 = yDai.rate0();
            } else {
                chi0 = chi;
                rate0 = rate;
            }

            profit = profit.add(divd(muld(_controller.systemDebtYDai(WETH, maturity), divd(rate, rate0)), chi0));
            profit = profit.add(divd(_controller.systemDebtYDai(CHAI, maturity), chi0));
            profit = profit.sub(divd(yDai.totalSupply(), chi0));
        }

        return profit;
    }

    /// @dev Settle system debt in MakerDAO and free remaining collateral.
    function settleTreasury() public {
        require(
            live == false,
            "Unwind: Unwind first"
        );
        (uint256 ink, uint256 art) = _vat.urns(WETH, address(_treasury));
        _vat.fork(                                               // Take the treasury vault
            WETH,
            address(_treasury),
            address(this),
            ink.toInt(),
            art.toInt()
        );
        _end.skim(WETH, address(this));                // Settle debts
        _end.free(WETH);                               // Free collateral
        uint256 gem = _vat.gem(WETH, address(this));          // Find out how much collateral we have now
        _wethJoin.exit(address(this), gem);                      // Take collateral out
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
        _end.cash(WETH, daiTokens);                // Exchange the dai for weth
        uint256 gem = _vat.gem(WETH, address(this));      // Find out how much collateral we have now
        _wethJoin.exit(address(this), gem);                  // Take collateral out
        cashedOut = true;

        _fix = _end.fix(WETH);
        _chi = _pot.chi();
    }

    /// @dev Settles a series position in Controller, and then returns any remaining collateral as weth using the unwind Dai to Weth price.
    function settle(bytes32 collateral, address user) public {
        require(settled && cashedOut, "Unwind: Not ready");

        uint256 debt = _controller.totalDebtDai(collateral, user);
        uint256 tokens = _controller.posted(collateral, user);
        _controller.grab(collateral, user, debt, tokens);

        uint256 remainder;
        if (collateral == WETH) {
            remainder = subFloorZero(tokens, muld(debt, _fix));
        } else if (collateral == CHAI) {
            remainder = muld(subFloorZero(muld(tokens, _chi), debt), _fix);
        }
        _weth.transfer(user, remainder);
    }

    /// @dev Redeems YDai for weth
    function redeem(uint256 maturity, uint256 yDaiAmount, address user) public {
        require(settled && cashedOut, "Unwind: Not ready");
        IYDai yDai = _controller.series(maturity);
        yDai.burn(user, yDaiAmount);
        _weth.transfer(
            user,
            muld(muld(yDaiAmount, yDai.chiGrowth()), _fix)
        );
    }
}