pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/Math.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IController.sol";
import "../helpers/DecimalMath.sol";
import "../helpers/SeriesRegistry.sol";
import "@nomiclabs/buidler/console.sol";

contract ControllerView is DecimalMath, SeriesRegistry {
    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IPot internal _pot;
    IController internal _controller;

    constructor (
        address controller_,
        address vat_,
        address pot_
    ) public {
        _vat = IVat(vat_);
        _pot = IPot(pot_);
        _controller = IController(controller_);
    }

    /// @dev Only valid collateral types are Weth and Chai.
    modifier validCollateral(bytes32 collateral) {
        require(
            collateral == WETH || collateral == CHAI,
            "CollateralProxy: Unrecognized collateral"
        );
        _;
    }

    /// @dev Maximum borrowing power of an user in dai for a given collateral
    //
    // powerOf[user](wad) = posted[user](wad) * oracle.price()(ray)
    //
    function powerOf(bytes32 collateral, address user) public view returns (uint256) {
        // dai = price * collateral
        uint256 posted = _controller.posted(collateral, user);
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);  // Stability fee and collateralization ratio for Weth
            return muld(posted, spot);
        } else if (collateral == CHAI) {
            return muld(posted, _pot.chi());
        }
        return 0;
    }

    function chiGrowth(uint256 maturity) public view returns(uint256){
        if (series[maturity].isMature() != true) return series[maturity].chi0();
        return Math.min(rateGrowth(maturity), divd(_pot.chi(), series[maturity].chi0()));
    }

    /// @dev Rate differential between maturity and now in RAY. Returns 1.0 if not mature.
    //
    //           rate_now
    // rateGrowth() = ----------
    //           rate_mat
    //
    function rateGrowth(uint256 maturity) public view returns(uint256){
        if (series[maturity].isMature() != true) return series[maturity].rate0();
        else {
            (, uint256 rateNow,,,) = _vat.ilks(WETH);
            return divd(rateNow, series[maturity].rate0());
        }
    }

    function debtDai(bytes32 collateral, uint256 maturity, address user) public view returns (uint256) {
        uint256 debtYDai = _controller.debtYDai(collateral, maturity, user);
        if (series[maturity].isMature()){
            if (collateral == WETH){
                return muld(debtYDai, rateGrowth(maturity));
            } else if (collateral == CHAI) {
                return muld(debtYDai, chiGrowth(maturity));
            } else {
                revert("Controller: Unsupported collateral");
            }
        } else {
            return debtYDai;
        }
    }

    /// @dev Returns the total debt of an user, for a given collateral, across all series, in Dai
    function totalDebtDai(bytes32 collateral, address user) public view returns (uint256) {
        uint256 totalDebt;
        for (uint256 i = 0; i < seriesIterator.length; i += 1) {
            totalDebt = totalDebt + debtDai(collateral, seriesIterator[i], user);
        }
        return totalDebt;
    }

    function locked(bytes32 collateral, address user) public view returns (uint256) {
        uint256 remainingPower = powerOf(collateral, user) - totalDebtDai(collateral, user);
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);  // Stability fee and collateralization ratio for Weth
            return divd(remainingPower, spot);
        } else if (collateral == CHAI) {
            return divd(remainingPower, _pot.chi());
        }
    }
}