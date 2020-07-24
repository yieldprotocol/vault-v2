// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IController.sol";
import "../interfaces/IMarket.sol";
import "../helpers/Delegable.sol";
import "../helpers/DecimalMath.sol";
import "@nomiclabs/buidler/console.sol";

/**
 * @dev The ControllerDai is a proxy contract of Controller that allows users to immediately sell borrowed yDai for Dai, and to sell Dai at market rates to repay YDai debt.
 * Users can delegate the control of their accounts in Controllers to any address.
 */
contract ControllerDai is Delegable(), DecimalMath {

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IPot internal _pot;
    IController internal _controller;
    IMarket internal _market;

    /// @dev The constructor links ControllerDai to vat, pot, controller and market.
    constructor (
        address vat_,
        address pot_,
        address controller_,
        address market_
    ) public {
        _vat = IVat(vat_);
        _pot = IPot(pot_);
        _controller = IController(controller_);
        _market = IMarket(market_);
    }

    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= 340282366920938463463374607431768211455,
            "Market: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, for a maximum cost in collateral.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address, { from: from })`.
    /// `from` can delegate to other addresses to use his vault with this proxy, with `controllerDai.addDelegate(someone, { from: from })`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param from Yield vault to lock collateral from.
    /// @param to Wallet to put the resulting Dai in.
    /// @param maximumCollateral Maximum amount of collateral to lock.
    /// @param daiToBorrow Exact amount of Dai that should be borrowed.
    function borrowDaiForMaximumCollateral(
        bytes32 collateral,
        uint256 maturity,
        address from,
        address to,
        uint256 maximumCollateral,
        uint256 daiToBorrow
    )
        public
        onlyHolderOrDelegate(from, "Controller: Only Holder Or Delegate")
        returns (uint256)
    {
        uint256 yDaiToBorrow = _market.buyDaiPreview(toUint128(daiToBorrow));
        uint256 yDaiInDai = _controller.inDai(collateral, maturity, yDaiToBorrow);
        uint256 requiredCollateral = daiToCollateral(collateral, yDaiInDai);
        require (requiredCollateral <= maximumCollateral);

        // The collateral for this borrow needs to have been posted beforehand
        _controller.borrow(collateral, maturity, from, address(this), yDaiToBorrow);
        _market.buyDai(address(this), to, toUint128(daiToBorrow));

        return requiredCollateral;
    }

    /// @dev Use a given amount of collateral to borrow yDai from Controller and sell it immediately for Dai, if a minimum amount of Dai can be obtained such.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address, { from: from })`.
    /// `from` can delegate to other addresses to use his vault with this proxy, with `controllerDai.addDelegate(someone, { from: from })`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param from Yield vault to lock collateral from.
    /// @param to Wallet to put the resulting Dai in.
    /// @param collateralToLock Amount of collateral to lock.
    /// @param minimumDaiToBorrow Minimum amount of Dai that should be borrowed.
    function borrowMinimumDaiForCollateral(
        bytes32 collateral,
        uint256 maturity,
        address from,
        address to,
        uint256 collateralToLock,
        uint256 minimumDaiToBorrow
    )
        public
        onlyHolderOrDelegate(from, "Controller: Only Holder Or Delegate")
        returns (uint256)
    {
        // This is actually debt in Dai, not redeemable
        uint256 daiBorrowingPower = collateralToDai(collateral, collateralToLock);
        uint256 yDaiBorrowingPower = _controller.inYDai(collateral, maturity, daiBorrowingPower);
        // The collateral for this borrow needs to have been posted beforehand
        _controller.borrow(collateral, maturity, from, address(this), yDaiBorrowingPower);
        uint256 boughtDai = _market.sellYDai(address(this), to, toUint128(yDaiBorrowingPower));
        require (boughtDai >= minimumDaiToBorrow);

        return boughtDai;
    }

    /// @dev Repay an amount of yDai debt in Controller using Dai exchanged for yDai at market rates, up to a maximum amount of Dai spent.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address, { from: from })`.
    /// `from` can delegate to other addresses to use his vault with this proxy, with `controllerDai.addDelegate(someone, { from: from })`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param from Wallet to take Dai from.
    /// @param to Yield Vault to repay yDai debt for.
    /// @param yDaiRepayment Amount of yDai debt to repay.
    /// @param maximumRepaymentInDai Maximum amount of Dai that should be spent on the repayment.
    function repayYDaiDebtForMaximumDai(
        bytes32 collateral,
        uint256 maturity,
        address from,
        address to,
        uint256 yDaiRepayment,
        uint256 maximumRepaymentInDai
    )
        public
        onlyHolderOrDelegate(from, "Controller: Only Holder Or Delegate")
        returns (uint256)
    {
        uint256 repaymentInDai = _market.buyYDai(from, to, toUint128(yDaiRepayment));
        require (repaymentInDai <= maximumRepaymentInDai);
        _controller.repayYDai(collateral, maturity, from, to, yDaiRepayment);

        return repaymentInDai;
    }

    /// @dev Repay an amount of yDai debt in Controller using a given amount of Dai exchanged for yDai at market rates, with a minimum of yDai debt required to be paid.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address, { from: from })`.
    /// `from` can delegate to other addresses to use his vault with this proxy, with `controllerDai.addDelegate(someone, { from: from })`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param from Wallet to take Dai from.
    /// @param to Yield Vault to repay yDai debt for.
    /// @param minimumYDaiRepayment Minimum amount of yDai debt to repay.
    /// @param repaymentInDai Exact amount of Dai that should be spent on the repayment.
    function repayMinimumYDaiDebtForDai(
        bytes32 collateral,
        uint256 maturity,
        address from,
        address to,
        uint256 minimumYDaiRepayment,
        uint256 repaymentInDai
    )
        public
        onlyHolderOrDelegate(from, "Controller: Only Holder Or Delegate")
        returns (uint256)
    {
        uint256 yDaiRepayment = _market.sellDai(from, to, toUint128(repaymentInDai));
        require (yDaiRepayment >= minimumYDaiRepayment);
        _controller.repayYDai(collateral, maturity, from, to, yDaiRepayment);

        return yDaiRepayment;
    }


    // TODO: Collapse the inDai(), inCollateral() and *Growth() functions.
    // TODO: Consider moving these functions to Controller
    /// @dev Calculate the amount of Dai that some collateral is worth at MakerDAO rates.
    /// @param collateral Valid collateral type.
    /// @param daiAmount Amount of Dai to convert into collateral.
    function daiToCollateral(bytes32 collateral, uint256 daiAmount) public returns (uint256) {
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);
            return divd(daiAmount, spot);
        } else if (collateral == CHAI) {
            uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
            return divd(daiAmount, chi);
        } else {
            revert("Controller: Unsupported collateral");
        }
    }

    /// @dev Calculate the amount of collateral that some Dai is worth at MakerDAO rates.
    /// @param collateral Valid collateral type.
    /// @param collateralAmount Amount of collateral to convert into Dai.
    function collateralToDai(bytes32 collateral, uint256 collateralAmount) public returns (uint256) {
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);
            return muld(collateralAmount, spot);
        } else if (collateral == CHAI) {
            uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
            return muld(collateralAmount, chi);
        } else {
            revert("Controller: Unsupported collateral");
        }
    }
}
