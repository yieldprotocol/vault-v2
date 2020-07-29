// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IController.sol";
import "../interfaces/IPool.sol";
import "../helpers/DecimalMath.sol";

/**
 * @dev The DaiProxy is a proxy contract of Controller that allows users to immediately sell borrowed yDai for Dai, and to sell Dai at pool rates to repay YDai debt.
 */
contract DaiProxy is DecimalMath {

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IERC20 internal _dai;
    IPot internal _pot;
    IERC20 internal _yDai;
    IController internal _controller;
    IPool internal _pool;

    /// @dev The constructor links ControllerDai to vat, pot, controller and pool.
    constructor (
        address vat_,
        address dai_,
        address pot_,
        address yDai_,
        address controller_,
        address pool_
    ) public {
        _vat = IVat(vat_);
        _dai = IERC20(dai_);
        _pot = IPot(pot_);
        _yDai = IERC20(yDai_);
        _controller = IController(controller_);
        _pool = IPool(pool_);

        _dai.approve(address(_pool), uint256(-1));
        _yDai.approve(address(_pool), uint256(-1));
    }

    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= 340282366920938463463374607431768211455,
            "Pool: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, for a maximum yDai debt.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param maximumYDai Maximum amount of YDai to borrow.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    function borrowDaiForMaximumYDai(
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 maximumYDai,
        uint256 daiToBorrow
    )
        public
        returns (uint256)
    {
        uint256 yDaiToBorrow = _pool.buyDaiPreview(toUint128(daiToBorrow));
        require (yDaiToBorrow <= maximumYDai, "DaiProxy: Too much yDai required");

        // The collateral for this borrow needs to have been posted beforehand
        _controller.borrow(collateral, maturity, msg.sender, address(this), yDaiToBorrow);
        _pool.buyDai(address(this), to, toUint128(daiToBorrow));

        return yDaiToBorrow;
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, if a minimum amount of Dai can be obtained such.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to sent the resulting Dai to.
    /// @param yDaiToBorrow Amount of yDai to borrow.
    /// @param minimumDaiToBorrow Minimum amount of Dai that should be borrowed.
    function borrowMinimumDaiForYDai(
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 yDaiToBorrow,
        uint256 minimumDaiToBorrow
    )
        public
        returns (uint256)
    {
        // The collateral for this borrow needs to have been posted beforehand
        _controller.borrow(collateral, maturity, msg.sender, address(this), yDaiToBorrow);
        uint256 boughtDai = _pool.sellYDai(address(this), to, toUint128(yDaiToBorrow));
        require (boughtDai >= minimumDaiToBorrow, "DaiProxy: Not enough Dai obtained");

        return boughtDai;
    }

    /// @dev Repay an amount of yDai debt in Controller using Dai exchanged for yDai at pool rates, up to a maximum amount of Dai spent.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param yDaiRepayment Amount of yDai debt to repay.
    /// @param maximumRepaymentInDai Maximum amount of Dai that should be spent on the repayment.
    function repayYDaiDebtForMaximumDai(
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 yDaiRepayment,
        uint256 maximumRepaymentInDai
    )
        public
        returns (uint256)
    {
        uint256 repaymentInDai = _pool.buyYDai(msg.sender, address(this), toUint128(yDaiRepayment));
        require (repaymentInDai <= maximumRepaymentInDai, "DaiProxy: Too much Dai required");
        _controller.repayYDai(collateral, maturity, address(this), to, yDaiRepayment);

        return repaymentInDai;
    }

    /// @dev Repay an amount of yDai debt in Controller using a given amount of Dai exchanged for yDai at pool rates, with a minimum of yDai debt required to be paid.
    /// Must have approved the operator with `controller.addDelegate(controllerDai.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param minimumYDaiRepayment Minimum amount of yDai debt to repay.
    /// @param repaymentInDai Exact amount of Dai that should be spent on the repayment.
    function repayMinimumYDaiDebtForDai(
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 minimumYDaiRepayment,
        uint256 repaymentInDai
    )
        public
        returns (uint256)
    {
        uint256 yDaiRepayment = _pool.sellDai(msg.sender, address(this), toUint128(repaymentInDai));
        require (yDaiRepayment >= minimumYDaiRepayment, "DaiProxy: Not enough yDai debt repaid");
        _controller.repayYDai(collateral, maturity, address(this), to, yDaiRepayment);

        return yDaiRepayment;
    }
}
