// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IController.sol";
import "../interfaces/IYDai.sol";
import "../helpers/DecimalMath.sol";

/// @dev Many of the functions in Controller are transactional due to `pot.drip()`.
/// ControllerView offers an option to retrieve the data in Controller, in a non-transactional mode,
/// provided that the caller doesn't mind that the values might be not exact.
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
    /// @param collateral Valid collateral type
    /// @param user Address of the user vault
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
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series.
    /// @param user Address of the user vault.
    function debtYDai(bytes32 collateral, uint256 maturity, address user)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        return _controller.debtYDai(collateral, maturity, user);
    }

    /// @dev Overall Debt for a collateral and maturity, in YDai
    /// Adding this one so that this contract can be used to display all data in Controller.
    /// @param collateral Valid collateral type
    /// @param maturity Maturity of an added series.
    function totalDebtYDai(bytes32 collateral, uint256 maturity)
        public view
        validCollateral(collateral)
        returns (uint256)
    {
        return _controller.totalDebtYDai(collateral, maturity);
    }

    /// @dev Borrowing power of an user in dai for a given collateral.
    /// @param collateral Valid collateral type.
    /// @param user Address of the user vault.
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

    /// @dev Chi differential between maturity and now in RAY. Returns 1.0 if not mature. Not transactional.
    /// If rateGrowth < chiGrowth, returns rate.
    //
    //          chi_now
    // chi() = ---------
    //          chi_mat
    //
    function chiGrowth(uint256 maturity)
        public view
        returns(uint256)
    {
        IYDai yDai = _controller.series(maturity);
        if (yDai.isMature() != true) return yDai.chi0();
        return Math.min(rateGrowth(maturity), divd(_pot.chi(), yDai.chi0()));
    }

    /// @dev Rate differential between maturity and now in RAY. Returns 1.0 if not mature. Not transactional.
    //
    //                 rate_now
    // rateGrowth() = ----------
    //                 rate_mat
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
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series.
    /// @param user Address of the user vault.
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
    /// @param collateral Valid collateral type.
    /// @param user Address of the user vault.
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

    /// @dev Returns the amount of collateral locked in borrowing operations.
    /// @param collateral Valid collateral type.
    /// @param user Address of the user vault.
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