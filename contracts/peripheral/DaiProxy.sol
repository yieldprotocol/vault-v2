// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IController.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IYDai.sol";
import "../helpers/DecimalMath.sol";

/**
 * @dev The DaiProxy is a proxy contract of Controller that allows users to immediately sell borrowed yDai for Dai, and to sell Dai at pool rates to repay YDai debt.
 */
contract DaiProxy is DecimalMath {

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IERC20 public dai;
    IController public controller;

    /// @dev The constructor links DaiProxy to dai and controller.
    constructor (
        address dai_,
        address controller_,
        address[] memory pools
    ) public {
        dai = IERC20(dai_);
        controller = IController(controller_);
        for (uint i = 0; i < pools.length; i++) {
            IYDai yDai = IPool(pools[i]).yDai();
            require(
                controller.containsSeries(yDai.maturity()),
                "DaiProxy: Mismatched Pool and Controller"
            );
            yDai.approve(pools[i], uint256(-1));
            dai.approve(pools[i], uint256(-1));            
        }
    }

    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= type(uint128).max,
            "Pool: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, for a maximum yDai debt.
    /// Must have approved the operator with `controller.addDelegate(daiProxy.address)`.
    /// @param pool The pool to trade in (and therefore yDai series to borrow)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param maximumYDai Maximum amount of YDai to borrow.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    function borrowDaiForMaximumYDai(
        address pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 maximumYDai,
        uint256 daiToBorrow
    )
        public
        returns (uint256)
    {
        IPool _pool = IPool(pool);
        uint256 yDaiToBorrow = _pool.buyDaiPreview(toUint128(daiToBorrow));
        require (yDaiToBorrow <= maximumYDai, "DaiProxy: Too much yDai required");

        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), yDaiToBorrow);
        _pool.buyDai(address(this), to, toUint128(daiToBorrow));

        return yDaiToBorrow;
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, for a maximum yDai debt.
    /// Uses an encoded signature for controller
    /// @param pool The pool to trade in (and therefore yDai series to borrow)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param maximumYDai Maximum amount of YDai to borrow.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    /// @param deadline Latest block timestamp for which the signature is valid
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    function borrowDaiForMaximumYDaiBySignature(
        address pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 maximumYDai,
        uint256 daiToBorrow,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        returns (uint256)
    {
        controller.addDelegateBySignature(msg.sender, address(this), deadline, v, r, s);
        return borrowDaiForMaximumYDai(pool, collateral, maturity, to, maximumYDai, daiToBorrow);
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, if a minimum amount of Dai can be obtained such.
    /// Must have approved the operator with `controller.addDelegate(daiProxy.address)`.
    /// @param pool The pool to trade in (and therefore yDai series to borrow)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to sent the resulting Dai to.
    /// @param yDaiToBorrow Amount of yDai to borrow.
    /// @param minimumDaiToBorrow Minimum amount of Dai that should be borrowed.
    function borrowMinimumDaiForYDai(
        address pool,
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
        controller.borrow(collateral, maturity, msg.sender, address(this), yDaiToBorrow);
        uint256 boughtDai = IPool(pool).sellYDai(address(this), to, toUint128(yDaiToBorrow));
        require (boughtDai >= minimumDaiToBorrow, "DaiProxy: Not enough Dai obtained");

        return boughtDai;
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, if a minimum amount of Dai can be obtained such.
    /// Uses an encoded signature for controller
    /// @param pool The pool to trade in (and therefore yDai series to borrow)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to sent the resulting Dai to.
    /// @param yDaiToBorrow Amount of yDai to borrow.
    /// @param minimumDaiToBorrow Minimum amount of Dai that should be borrowed.
    /// @param deadline Latest block timestamp for which the signature is valid
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    function borrowMinimumDaiForYDaiBySignature(
        address pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 yDaiToBorrow,
        uint256 minimumDaiToBorrow,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        returns (uint256)
    {
        controller.addDelegateBySignature(msg.sender, address(this), deadline, v, r, s);
        return borrowMinimumDaiForYDai(pool, collateral, maturity, to, yDaiToBorrow, minimumDaiToBorrow);
    }

    /// @dev Repay an amount of yDai debt in Controller using Dai exchanged for yDai at pool rates, up to a maximum amount of Dai spent.
    /// Must have approved the operator with `pool.addDelegate(daiProxy.address)`.
    /// @param pool The pool to trade in (and therefore yDai series to repay)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param yDaiRepayment Amount of yDai debt to repay.
    /// @param maximumRepaymentInDai Maximum amount of Dai that should be spent on the repayment.
    function repayYDaiDebtForMaximumDai(
        address pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 yDaiRepayment,
        uint256 maximumRepaymentInDai
    )
        public
        returns (uint256)
    {
        uint256 repaymentInDai = IPool(pool).buyYDai(msg.sender, address(this), toUint128(yDaiRepayment));
        require (repaymentInDai <= maximumRepaymentInDai, "DaiProxy: Too much Dai required");
        controller.repayYDai(collateral, maturity, address(this), to, yDaiRepayment);

        return repaymentInDai;
    }

    /// @dev Repay an amount of yDai debt in Controller using Dai exchanged for yDai at pool rates, up to a maximum amount of Dai spent.
    /// Uses an encoded signature for pool
    /// @param pool The pool to trade in (and therefore yDai series to repay)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param yDaiRepayment Amount of yDai debt to repay.
    /// @param maximumRepaymentInDai Maximum amount of Dai that should be spent on the repayment.
    /// @param deadline Latest block timestamp for which the signature is valid
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    function repayYDaiDebtForMaximumDaiBySignature(
        address pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 yDaiRepayment,
        uint256 maximumRepaymentInDai,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        returns (uint256)
    {
        IPool(pool).addDelegateBySignature(msg.sender, address(this), deadline, v, r, s);
        return repayYDaiDebtForMaximumDai(pool, collateral, maturity, to, yDaiRepayment, maximumRepaymentInDai);
    }

    /// @dev Repay an amount of yDai debt in Controller using a given amount of Dai exchanged for yDai at pool rates, with a minimum of yDai debt required to be paid.
    /// Must have approved the operator with `pool.addDelegate(daiProxy.address)`.
    /// @param pool The pool to trade in (and therefore yDai series to repay)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param minimumYDaiRepayment Minimum amount of yDai debt to repay.
    /// @param repaymentInDai Exact amount of Dai that should be spent on the repayment.
    function repayMinimumYDaiDebtForDai(
        address pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 minimumYDaiRepayment,
        uint256 repaymentInDai
    )
        public
        returns (uint256)
    {
        uint256 yDaiRepayment = IPool(pool).sellDai(msg.sender, address(this), toUint128(repaymentInDai));
        require (yDaiRepayment >= minimumYDaiRepayment, "DaiProxy: Not enough yDai debt repaid");
        controller.repayYDai(collateral, maturity, address(this), to, yDaiRepayment);

        return yDaiRepayment;
    }

    /// @dev Repay an amount of yDai debt in Controller using a given amount of Dai exchanged for yDai at pool rates, with a minimum of yDai debt required to be paid.
    /// Uses an encoded signature for pool
    /// @param pool The pool to trade in (and therefore yDai series to repay)
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param minimumYDaiRepayment Minimum amount of yDai debt to repay.
    /// @param repaymentInDai Exact amount of Dai that should be spent on the repayment.
    /// @param deadline Latest block timestamp for which the signature is valid
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    function repayMinimumYDaiDebtForDaiBySignature(
        address pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 minimumYDaiRepayment,
        uint256 repaymentInDai,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        returns (uint256)
    {
        IPool(pool).addDelegateBySignature(msg.sender, address(this), deadline, v, r, s);
        return repayMinimumYDaiDebtForDai(pool, collateral, maturity, to, minimumYDaiRepayment, repaymentInDai);
    }
}
