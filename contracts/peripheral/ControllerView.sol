// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IController.sol";
import "../interfaces/IYDai.sol";
import "../helpers/DecimalMath.sol";
import "@nomiclabs/buidler/console.sol";

contract ControllerView is DecimalMath {
    using SafeMath for uint256;

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IPot internal _pot;
    IController internal _controller;

    constructor (
        address vat_,
        address pot_,
        address controller_
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

    /// @dev Posted collateral for an user
    /// Adding this one so that this contract can be used to display all data in Controller
    function posted(bytes32 collateral, address user)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        return _controller.posted(collateral, user);
    }

    /// @dev Posted chai for the overall system
    /// Adding this one so that this contract can be used to display all data in Controller
    function totalChaiPosted()
        public view
        returns (uint256)
    {
        return _controller.totalChaiPosted();
    }

    /// @dev Debt for a collateral, maturity and user, in YDai
    /// Adding this one so that this contract can be used to display all data in Controller
    function debtYDai(bytes32 collateral, uint256 maturity, address user)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        return _controller.debtYDai(collateral, maturity, user);
    }

    /// @dev Overall Debt for a collateral and maturity, in YDai
    /// Adding this one so that this contract can be used to display all data in Controller
    function totalDebtYDai(bytes32 collateral, uint256 maturity)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        return _controller.totalDebtYDai(collateral, maturity);
    }

    /// @dev Maximum borrowing power of an user in dai for a given collateral
    function powerOf(bytes32 collateral, address user)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        // dai = price * collateral
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);  // Stability fee and collateralization ratio for Weth
            return muld(posted(collateral, user), spot);
        } else if (collateral == CHAI) {
            return muld(posted(collateral, user), _pot.chi());
        }
        return 0;
    }

    function chiGrowth(uint256 maturity)
        public view
        returns(uint256)
    {
        IYDai yDai = _controller.series(maturity);
        if (yDai.isMature() != true) return yDai.chi0();
        return Math.min(rateGrowth(maturity), divd(_pot.chi(), yDai.chi0()));
    }

    /// @dev Rate differential between maturity and now in RAY. Returns 1.0 if not mature.
    //
    //           rate_now
    // rateGrowth() = ----------
    //           rate_mat
    //
    function rateGrowth(uint256 maturity)
        public view
        returns(uint256)
    {
        IYDai yDai = _controller.series(maturity);
        if (yDai.isMature() != true) return yDai.rate0();
        else {
            (, uint256 rateNow,,,) = _vat.ilks(WETH);
            return divd(rateNow, yDai.rate0());
        }
    }

    /// @dev Debt for a collateral, maturity and user, in Dai
    function debtDai(bytes32 collateral, uint256 maturity, address user)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        IYDai yDai = _controller.series(maturity);
        if (yDai.isMature()){
            if (collateral == WETH){
                return muld(debtYDai(collateral, maturity, user), rateGrowth(maturity));
            } else if (collateral == CHAI) {
                return muld(debtYDai(collateral, maturity, user), chiGrowth(maturity));
            } else {
                revert("Controller: Unsupported collateral");
            }
        } else {
            return debtYDai(collateral, maturity, user);
        }
    }

    /// @dev Returns the total debt of an user, for a given collateral, across all series, in Dai
    function totalDebtDai(bytes32 collateral, address user)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        uint256 totalDebt;
        for (uint256 i = 0; i < _controller.totalSeries(); i += 1) {
            uint256 maturity = _controller.seriesIterator(i);
            totalDebt = totalDebt + debtDai(collateral, maturity, user);
        }
        return totalDebt;
    }

    function locked(bytes32 collateral, address user)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);  // Stability fee and collateralization ratio for Weth
            return divd(totalDebtDai(collateral, user), spot);
        } else if (collateral == CHAI) {
            return divd(totalDebtDai(collateral, user), _pot.chi());
        }
    }
}
