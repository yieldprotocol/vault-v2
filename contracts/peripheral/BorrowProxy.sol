// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IWeth.sol";
import "../interfaces/IDai.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IPool.sol";
import "@nomiclabs/buidler/console.sol";

interface ControllerLike {
    function treasury() external view returns (ITreasury);
    function weth() external view returns (IWeth);
    function dai() external view returns (IDai);
    function post(bytes32, address, address, uint256) external;
    function withdraw(bytes32, address, address, uint256) external;
    function borrow(bytes32, uint256, address, address, uint256) external;
    function repayDai(bytes32, uint256, address, address, uint256) external returns (uint256);
    function addDelegateBySignature(address, address, uint, uint8, bytes32, bytes32) external;
}

library SafeCast {
    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= type(uint128).max,
            "YieldProxy: Cast overflow"
        );
        return uint128(x);
    }
}


contract BorrowProxy {
    using SafeCast for uint256;

    IWeth public immutable weth;
    IDai public immutable dai;
    ControllerLike public immutable controller;
    address public immutable treasury;

    bytes32 public constant WETH = "ETH-A";

    constructor(address weth_, address dai_, address treasury_, address controller_) public {
        controller = ControllerLike(controller_);
        treasury = treasury_;

        weth = IWeth(weth_);
        dai = IDai(dai_);

        IWeth(weth_).approve(treasury_, uint(-1));
    }

    /// @dev The WETH9 contract will send ether to YieldProxy on `weth.withdraw` using this function.
    receive() external payable { }

    /// @dev Users use `post` in YieldProxy to post ETH to the Controller (amount = msg.value), which will be converted to Weth here.
    /// @param to Yield Vault to deposit collateral in.
    function post(address to)
        external payable {
        weth.deposit{ value: msg.value }();
        controller.post(WETH, address(this), to, msg.value);
    }

    /// @dev Users wishing to withdraw their Weth as ETH from the Controller should use this function.
    /// Users must have called `controller.addDelegate(yieldProxy.address)` to authorize YieldProxy to act in their behalf.
    /// @param to Wallet to send Eth to.
    /// @param amount Amount of weth to move.
    function withdraw(address payable to, uint256 amount)
        public {
        controller.withdraw(WETH, msg.sender, address(this), amount);
        weth.withdraw(amount);
        to.transfer(amount);
    }

    /// @dev Borrow fyDai from Controller and sell it immediately for Dai, for a maximum fyDai debt.
    /// Must have approved the operator with `controller.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param maximumFYDai Maximum amount of FYDai to borrow.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    function borrowDaiForMaximumFYDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 maximumFYDai,
        uint256 daiToBorrow
    )
        public
        returns (uint256)
    {
        uint256 fyDaiToBorrow = pool.buyDaiPreview(daiToBorrow.toUint128());
        require (fyDaiToBorrow <= maximumFYDai, "YieldProxy: Too much fyDai required");

        // allow the pool to pull FYDai/dai from us for LPing
        if (pool.fyDai().allowance(address(this), address(pool)) < type(uint256).max) {
            pool.fyDai().approve(address(pool), type(uint256).max);
        }

        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), fyDaiToBorrow);
        pool.buyDai(address(this), to, daiToBorrow.toUint128());

        return fyDaiToBorrow;
    }

    /// --------------------------------------------------
    /// Signature management and signature method wrappers
    /// --------------------------------------------------

    /// @dev Unpack r, s and v from a `bytes` signature
    function unpack(bytes memory signature) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
    }

    function authorizeController(bytes memory controllerSig) public {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (controllerSig.length > 0) {
            (r, s, v) = unpack(controllerSig);
            controller.addDelegateBySignature(msg.sender, address(this), uint(-1), v, r, s);
        }
    }

    function authorizeDai(bytes memory daiSig) public {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (daiSig.length > 0) {
            (r, s, v) = unpack(daiSig);
            dai.permit(msg.sender, address(treasury), dai.nonces(msg.sender), uint(-1), true, v, r, s);
        }
    }

    /// @dev Users wishing to withdraw their Weth as ETH from the Controller should use this function.
    /// Users must have called `controller.addDelegate(yieldProxy.address)` to authorize YieldProxy to act in their behalf.
    /// @param to Wallet to send Eth to.
    /// @param amount Amount of weth to move.
    /// @param controllerSig packed signature for delegation of this proxy in the controller.
    function withdrawWithSignature(address payable to, uint256 amount, bytes memory controllerSig)
        public {
        authorizeController(controllerSig);
        withdraw(to, amount);
    }

    /// @dev Borrow fyDai from Controller and sell it immediately for Dai, for a maximum fyDai debt.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param maximumFYDai Maximum amount of FYDai to borrow.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    /// @param controllerSig packed signature for delegation of this proxy in the controller.
    function borrowDaiForMaximumFYDaiWithSignature(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 maximumFYDai,
        uint256 daiToBorrow,
        bytes memory controllerSig
    )
        public
        returns (uint256)
    {
        authorizeController(controllerSig);
        return borrowDaiForMaximumFYDai(pool, collateral, maturity, to, maximumFYDai, daiToBorrow);
    }

    /// @dev Burns Dai from caller to repay debt in a Yield Vault.
    /// User debt is decreased for the given collateral and fyDai series, in Yield vault `to`.
    /// The amount of debt repaid changes according to series maturity and MakerDAO rate and chi, depending on collateral type.
    /// `A signature is provided as a parameter to this function, so that `dai.approve()` doesn't need to be called.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield vault to repay debt for.
    /// @param daiAmount Amount of Dai to use for debt repayment.
    /// @param daiSig packed signature for permit of dai transfers to this proxy.
    /// @param controllerSig packed signature for delegation of this proxy in the controller.
    function repayDaiWithSignature(bytes32 collateral, uint256 maturity, address to, uint256 daiAmount, bytes memory daiSig, bytes memory controllerSig)
        external
        returns(uint256)
    {
        authorizeController(controllerSig);
        authorizeDai(daiSig);
        controller.repayDai(collateral, maturity, msg.sender, to, daiAmount);
    }
}
