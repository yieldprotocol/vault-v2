// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IWeth.sol";
import "../interfaces/IDai.sol";
import "../interfaces/IFYDai.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IController.sol";
import "../interfaces/IPool.sol";
import "../helpers/SafeCast.sol";
import "../helpers/YieldAuth.sol";


contract BorrowProxy {
    using SafeCast for uint256;
    using YieldAuth for IDai;
    using YieldAuth for IFYDai;
    using YieldAuth for IController;
    using YieldAuth for IPool;

    IWeth public immutable weth;
    IDai public immutable dai;
    IController public immutable controller;
    address public immutable treasury;

    bytes32 public constant WETH = "ETH-A";

    constructor(IController _controller) public {
        ITreasury _treasury = _controller.treasury();
        weth = _treasury.weth();
        dai = _treasury.dai();
        treasury = address(_treasury);
        controller = _controller;
    }

    /// @dev The WETH9 contract will send ether to BorrowProxy on `weth.withdraw` using this function.
    receive() external payable { }

    /// @dev Users use `post` in BorrowProxy to post ETH to the Controller (amount = msg.value), which will be converted to Weth here.
    /// @param to Yield Vault to deposit collateral in.
    function post(address to)
        external payable {
        // Approvals in the constructor don't work for contracts calling this via `addDelegatecall`
        if (weth.allowance(address(this), treasury) < type(uint256).max) weth.approve(treasury, type(uint256).max);

        weth.deposit{ value: msg.value }();
        controller.post(WETH, address(this), to, msg.value);
    }

    /// @dev Users wishing to withdraw their Weth as ETH from the Controller should use this function.
    /// Users must have called `controller.addDelegate(borrowProxy.address)` or `withdrawWithSignature` to authorize BorrowProxy to act in their behalf.
    /// @param to Wallet to send Eth to.
    /// @param amount Amount of weth to move.
    function withdraw(address payable to, uint256 amount)
        public {
        controller.withdraw(WETH, msg.sender, address(this), amount);
        weth.withdraw(amount);
        to.transfer(amount);
    }

    /// @dev Borrow fyDai from Controller and sell it immediately for Dai, for a maximum fyDai debt.
    /// Must have approved the operator with `controller.addDelegate(borrowProxy.address)` or with `borrowDaiForMaximumFYDaiWithSignature`.
    /// Caller must have called `borrowDaiForMaximumFYDaiWithSignature` at least once before to set proxy approvals.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    /// @param maximumFYDai Maximum amount of FYDai to borrow.
    function borrowDaiForMaximumFYDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 daiToBorrow,
        uint256 maximumFYDai
    )
        public
        returns (uint256)
    {
        uint256 fyDaiToBorrow = pool.buyDaiPreview(daiToBorrow.toUint128());
        require (fyDaiToBorrow <= maximumFYDai, "BorrowProxy: Too much fyDai required");

        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), fyDaiToBorrow);
        pool.buyDai(address(this), to, daiToBorrow.toUint128());

        return fyDaiToBorrow;
    }

    /// @dev Sell fyDai for Dai
    /// Caller must have approved the fyDai transfer with `fyDai.approve(fyDaiUsed)` or with `sellFYDaiWithSignature`.
    /// Caller must have approved the proxy using`pool.addDelegate(borrowProxy)` or with `sellFYDaiWithSignature`.
    /// @param to Wallet receiving the dai being bought
    /// @param fyDaiIn Amount of fyDai being sold
    /// @param minDaiOut Minimum amount of dai being bought
    function sellFYDai(IPool pool, address to, uint128 fyDaiIn, uint128 minDaiOut)
        public
        returns(uint256)
    {
        uint256 daiOut = pool.sellFYDai(msg.sender, to, fyDaiIn);
        require(
            daiOut >= minDaiOut,
            "BorrowProxy: Limit not reached"
        );
        return daiOut;
    }

    /// @dev Sell Dai for fyDai
    /// Caller must have approved the dai transfer with `dai.approve(fyDaiUsed)` or with `sellDaiWithSignature`.
    /// Caller must have approved the proxy using`pool.addDelegate(borrowProxy)` or with `sellDaiWithSignature`.
    /// @param to Wallet receiving the fyDai being bought
    /// @param daiIn Amount of dai being sold
    /// @param minFYDaiOut Minimum amount of fyDai being bought
    function sellDai(IPool pool, address to, uint128 daiIn, uint128 minFYDaiOut)
        public
        returns(uint256)
    {
        uint256 fyDaiOut = pool.sellDai(msg.sender, to, daiIn);
        require(
            fyDaiOut >= minFYDaiOut,
            "BorrowProxy: Limit not reached"
        );
        return fyDaiOut;
    }

    /// --------------------------------------------------
    /// Signature method wrappers
    /// --------------------------------------------------

    /// @dev Determine whether all approvals and signatures are in place for `withdrawWithSignature`.
    /// `return[0]` is always `true`, meaning that no proxy approvals are ever needed.
    /// If `return[1]` is `false`, `withdrawWithSignature` must be called with a controller signature.
    /// If `return` is `(true, true)`, `withdrawWithSignature` won't fail because of missing approvals or signatures.
    function withdrawCheck() public view returns (bool, bool) {
        bool approvals = true; // sellFYDai doesn't need proxy approvals
        bool controllerSig = controller.delegated(msg.sender, address(this));
        return (approvals, controllerSig);
    }

    /// @dev Users wishing to withdraw their Weth as ETH from the Controller should use this function.
    /// @param to Wallet to send Eth to.
    /// @param amount Amount of weth to move.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    function withdrawWithSignature(address payable to, uint256 amount, bytes memory controllerSig)
        public {
        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        withdraw(to, amount);
    }

    /// @dev Determine whether all approvals and signatures are in place for `borrowDaiForMaximumFYDai` with a given pool.
    /// If `return[0]` is `false`, calling `borrowDaiForMaximumFYDaiWithSignature` will set the approvals.
    /// If `return[1]` is `false`, `borrowDaiForMaximumFYDaiWithSignature` must be called with a controller signature
    /// If `return` is `(true, true)`, `borrowDaiForMaximumFYDai` won't fail because of missing approvals or signatures.
    function borrowDaiForMaximumFYDaiCheck(IPool pool) public view returns (bool, bool) {
        bool approvals = pool.fyDai().allowance(address(this), address(pool)) >= type(uint112).max;
        bool controllerSig = controller.delegated(msg.sender, address(this));
        return (approvals, controllerSig);
    }

    /// @dev Set proxy approvals for `borrowDaiForMaximumFYDai` with a given pool.
    function borrowDaiForMaximumFYDaiApprove(IPool pool) public {
        // allow the pool to pull FYDai/dai from us for LPing
        if (pool.fyDai().allowance(address(this), address(pool)) < type(uint112).max) pool.fyDai().approve(address(pool), type(uint256).max);
    }

    /// @dev Borrow fyDai from Controller and sell it immediately for Dai, for a maximum fyDai debt.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    /// @param maximumFYDai Maximum amount of FYDai to borrow.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    function borrowDaiForMaximumFYDaiWithSignature(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 daiToBorrow,
        uint256 maximumFYDai,
        bytes memory controllerSig
    )
        public
        returns (uint256)
    {
        borrowDaiForMaximumFYDaiApprove(pool);
        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        return borrowDaiForMaximumFYDai(pool, collateral, maturity, to, daiToBorrow, maximumFYDai);
    }

    /// @dev Determine whether all approvals and signatures are in place for `repayDaiWithSignature`.
    /// `return[0]` is always `true`, meaning that no proxy approvals are ever needed.
    /// If `return[1]` is `false`, `repayDaiWithSignature` must be called with a dai permit signature.
    /// If `return[2]` is `false`, `repayDaiWithSignature` must be called with a controller signature.
    /// If `return` is `(true, true, true)`, `repayDaiWithSignature` won't fail because of missing approvals or signatures.
    /// If `return` is `(true, true, any)`, `controller.repayDai` can be called directly and won't fail because of missing approvals or signatures.
    function repayDaiCheck() public view returns (bool, bool, bool) {
        bool approvals = true; // repayDai doesn't need proxy approvals
        bool daiSig = dai.allowance(msg.sender, treasury) == type(uint256).max;
        bool controllerSig = controller.delegated(msg.sender, address(this));
        return (approvals, daiSig, controllerSig);
    }

    /// @dev Burns Dai from caller to repay debt in a Yield Vault.
    /// User debt is decreased for the given collateral and fyDai series, in Yield vault `to`.
    /// The amount of debt repaid changes according to series maturity and MakerDAO rate and chi, depending on collateral type.
    /// `A signature is provided as a parameter to this function, so that `dai.approve()` doesn't need to be called.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield vault to repay debt for.
    /// @param daiAmount Amount of Dai to use for debt repayment.
    /// @param daiSig packed signature for permit of dai transfers to this proxy. Ignored if '0x'.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    function repayDaiWithSignature(bytes32 collateral, uint256 maturity, address to, uint256 daiAmount, bytes memory daiSig, bytes memory controllerSig)
        external
        returns(uint256)
    {
        if (daiSig.length > 0) dai.permitPackedDai(treasury, daiSig);
        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        controller.repayDai(collateral, maturity, msg.sender, to, daiAmount);
    }

    /// @dev Determine whether all approvals and signatures are in place for `sellFYDai`.
    /// `return[0]` is always `true`, meaning that no proxy approvals are ever needed.
    /// If `return[1]` is `false`, `sellFYDaiWithSignature` must be called with a fyDai permit signature.
    /// If `return[2]` is `false`, `sellFYDaiWithSignature` must be called with a pool signature.
    /// If `return` is `(true, true, true)`, `sellFYDai` won't fail because of missing approvals or signatures.
    function sellFYDaiCheck(IPool pool) public view returns (bool, bool, bool) {
        bool approvals = true; // sellFYDai doesn't need proxy approvals
        bool fyDaiSig = pool.fyDai().allowance(msg.sender, address(pool)) >= type(uint112).max;
        bool poolSig = pool.delegated(msg.sender, address(this));
        return (approvals, fyDaiSig, poolSig);
    }

    /// @dev Sell fyDai for Dai
    /// @param to Wallet receiving the dai being bought
    /// @param fyDaiIn Amount of fyDai being sold
    /// @param minDaiOut Minimum amount of dai being bought
    /// @param fyDaiSig packed signature for approving fyDai transfers to a pool. Ignored if '0x'.
    /// @param poolSig packed signature for delegation of this proxy in a pool. Ignored if '0x'.
    function sellFYDaiWithSignature(IPool pool, address to, uint128 fyDaiIn, uint128 minDaiOut, bytes memory fyDaiSig, bytes memory poolSig)
        public
        returns(uint256)
    {
        if (fyDaiSig.length > 0) pool.fyDai().permitPacked(address(pool), fyDaiSig);
        if (poolSig.length > 0) pool.addDelegatePacked(poolSig);
        return sellFYDai(pool, to, fyDaiIn, minDaiOut);
    }

    /// @dev Determine whether all approvals and signatures are in place for `sellDai`.
    /// `return[0]` is always `true`, meaning that no proxy approvals are ever needed.
    /// If `return[1]` is `false`, `sellDaiWithSignature` must be called with a dai permit signature.
    /// If `return[2]` is `false`, `sellDaiWithSignature` must be called with a pool signature.
    /// If `return` is `(true, true, true)`, `sellDai` won't fail because of missing approvals or signatures.
    function sellDaiCheck(IPool pool) public view returns (bool, bool, bool) {
        bool approvals = true; // sellDai doesn't need proxy approvals
        bool daiSig = dai.allowance(msg.sender, address(pool)) == type(uint256).max;
        bool poolSig = pool.delegated(msg.sender, address(this));
        return (approvals, daiSig, poolSig);
    }

    /// @dev Sell Dai for fyDai
    /// @param to Wallet receiving the fyDai being bought
    /// @param daiIn Amount of dai being sold
    /// @param minFYDaiOut Minimum amount of fyDai being bought
    /// @param daiSig packed signature for approving Dai transfers to a pool. Ignored if '0x'.
    /// @param poolSig packed signature for delegation of this proxy in a pool. Ignored if '0x'.
    function sellDaiWithSignature(IPool pool, address to, uint128 daiIn, uint128 minFYDaiOut, bytes memory daiSig, bytes memory poolSig)
        external
        returns(uint256)
    {
        if (daiSig.length > 0) dai.permitPackedDai(address(pool), daiSig);
        if (poolSig.length > 0) pool.addDelegatePacked(poolSig);
        return sellDai(pool, to, daiIn, minFYDaiOut);
    }
}
