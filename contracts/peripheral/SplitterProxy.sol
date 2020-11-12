// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IController.sol";
import "../interfaces/IWeth.sol";
import "../interfaces/IGemJoin.sol";
import "../interfaces/IDaiJoin.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IFYDai.sol";
import "../interfaces/IFlashMinter.sol";
import "../helpers/DecimalMath.sol";
import "../helpers/SafeCast.sol";
import "../helpers/YieldAuth.sol";


contract YieldProxy is DecimalMath, IFlashMinter {
    using SafeCast for uint256;
    using YieldAuth for IController;

    IVat public immutable vat;
    IWeth public immutable weth;
    IERC20 public immutable dai;
    IGemJoin public immutable wethJoin;
    IDaiJoin public immutable daiJoin;
    IController public immutable controller;
    address public immutable treasury;

    bytes32 public constant WETH = "ETH-A";
    bool public constant MTY = true;
    bool public constant YTM = false;

    constructor(address controller_) public {
        IController _controller = IController(controller_);
        ITreasury _treasury = _controller.treasury();

        weth = _treasury.weth();
        dai = _treasury.dai();
        daiJoin = _treasury.daiJoin();
        wethJoin = _treasury.wethJoin();
        vat = _treasury.vat();

        controller = _controller;
        treasury = address(_treasury);
    }

    // YieldProxy: Maker to Yield proxy

    /// @dev Transfer debt and collateral from MakerDAO to Yield
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore fyDai series to borrow)
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    function makerToYield(IPool pool, uint256 wethAmount, uint256 daiAmount) public {
        // The user specifies the fyDai he wants to mint to cover his maker debt, the weth to be passed on as collateral, and the dai debt to move
        (uint256 ink, uint256 art) = vat.urns(WETH, msg.sender);
        (, uint256 rate,,,) = vat.ilks("ETH-A");
        require(
            daiAmount <= muld(art, rate),
            "YieldProxy: Not enough debt in Maker"
        );
        require(
            wethAmount <= ink,
            "YieldProxy: Not enough collateral in Maker"
        );
        // Flash mint the fyDai
        IFYDai fyDai = pool.fyDai();
        fyDai.flashMint(
            fyDaiForDai(pool, daiAmount),
            abi.encode(MTY, pool, msg.sender, wethAmount, daiAmount)
        );
    }

    /// @dev Transfer debt and collateral from Yield to MakerDAO
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore fyDai series to migrate)
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    /// @param fyDaiAmount fyDai debt to move from Yield to MakerDAO.
    function yieldToMaker(IPool pool, uint256 wethAmount, uint256 fyDaiAmount) public {
        IFYDai fyDai = pool.fyDai();

        // The user specifies the fyDai he wants to move, and the weth to be passed on as collateral
        require(
            fyDaiAmount <= controller.debtFYDai(WETH, fyDai.maturity(), msg.sender),
            "YieldProxy: Not enough debt in Yield"
        );
        require(
            wethAmount <= controller.posted(WETH, msg.sender),
            "YieldProxy: Not enough collateral in Yield"
        );
        // Flash mint the fyDai
        fyDai.flashMint(
            fyDaiAmount,
            abi.encode(YTM, pool, msg.sender, wethAmount, 0)
        ); // The daiAmount encoded is ignored
    }

    /// @dev Callback from `FYDai.flashMint()`
    function executeOnFlashMint(uint256 fyDaiAmount, bytes calldata data) external override {
        (bool direction, IPool pool, address user, uint256 wethAmount, uint256 daiAmount) = 
            abi.decode(data, (bool, IPool, address, uint256, uint256));
        require(msg.sender == address(IPool(pool).fyDai()), "YieldProxy: Restricted callback");

        if(direction == MTY) _makerToYield(pool, user, wethAmount, daiAmount);
        if(direction == YTM) _yieldToMaker(pool, user, wethAmount, fyDaiAmount);
    }

    /// @dev Minimum weth needed to collateralize an amount of dai in MakerDAO
    function wethForDai(uint256 daiAmount) public view returns (uint256) {
        (,, uint256 spot,,) = vat.ilks("ETH-A");
        return divd(daiAmount, spot);
    }

    /// @dev Minimum weth needed to collateralize an amount of fyDai in Yield. Yes, it's the same formula.
    function wethForFYDai(uint256 fyDaiAmount) public view returns (uint256) {
        (,, uint256 spot,,) = vat.ilks("ETH-A");
        return divd(fyDaiAmount, spot);
    }

    /// @dev Amount of fyDai debt that will result from migrating Dai debt from MakerDAO to Yield
    function fyDaiForDai(IPool pool, uint256 daiAmount) public view returns (uint256) {
        return pool.buyDaiPreview(daiAmount.toUint128());
    }

    /// @dev Amount of dai debt that will result from migrating fyDai debt from Yield to MakerDAO
    function daiForFYDai(IPool pool, uint256 fyDaiAmount) public view returns (uint256) {
        return pool.buyFYDaiPreview(fyDaiAmount.toUint128());
    }

    /// @dev Internal function to transfer debt and collateral from MakerDAO to Yield
    /// @param pool The pool to trade in (and therefore fyDai series to borrow)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    function _makerToYield(IPool pool, address user, uint256 wethAmount, uint256 daiAmount) internal {
        IFYDai fyDai = IFYDai(pool.fyDai());

        // Pool should take exactly all fyDai flash minted. YieldProxy will hold the dai temporarily
        uint256 fyDaiSold = pool.buyDai(address(this), address(this), daiAmount.toUint128());

        daiJoin.join(user, daiAmount);      // Put the Dai in Maker
        (, uint256 rate,,,) = vat.ilks("ETH-A");
        vat.frob(                           // Pay the debt and unlock collateral in Maker
            "ETH-A",
            user,
            user,
            user,
            -wethAmount.toInt256(),               // Removing Weth collateral
            -divdrup(daiAmount, rate).toInt256()  // Removing Dai debt
        );

        vat.flux("ETH-A", user, address(this), wethAmount);             // Remove the collateral from Maker
        wethJoin.exit(address(this), wethAmount);                       // Hold the weth in YieldProxy
        controller.post(WETH, address(this), user, wethAmount);         // Add the collateral to Yield
        controller.borrow(WETH, fyDai.maturity(), user, address(this), fyDaiSold); // Borrow the fyDai
    }


    /// @dev Internal function to transfer debt and collateral from Yield to MakerDAO
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore fyDai series to migrate)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    /// @param fyDaiAmount fyDai debt to move from Yield to MakerDAO.
    function _yieldToMaker(IPool pool, address user, uint256 wethAmount, uint256 fyDaiAmount) internal {
        IFYDai fyDai = IFYDai(pool.fyDai());

        // Pay the Yield debt - YieldProxy pays FYDai to remove the debt of `user`
        // Controller should take exactly all fyDai flash minted.
        controller.repayFYDai(WETH, fyDai.maturity(), address(this), user, fyDaiAmount);

        // Withdraw the collateral from Yield, YieldProxy will hold it
        controller.withdraw(WETH, user, address(this), wethAmount);

        // Post the collateral to Maker, in the `user` vault
        wethJoin.join(user, wethAmount);

        // We are going to need to buy the FYDai back with Dai borrowed from Maker
        uint256 daiAmount = pool.buyFYDaiPreview(fyDaiAmount.toUint128());

        // Borrow the Dai from Maker
        (, uint256 rate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee for Weth
        vat.frob(
            "ETH-A",
            user,
            user,
            user,
            wethAmount.toInt256(),                   // Adding Weth collateral
            divdrup(daiAmount, rate).toInt256()      // Adding Dai debt
        );
        vat.move(user, address(this), daiAmount.mul(UNIT)); // Transfer the Dai to YieldProxy within MakerDAO, in RAD
        daiJoin.exit(address(this), daiAmount);             // YieldProxy will hold the dai temporarily

        // Sell the Dai for FYDai at Pool - It should make up for what was taken with repayYdai
        pool.buyFYDai(address(this), address(this), fyDaiAmount.toUint128());
    }

    /// --------------------------------------------------
    /// Signature method wrappers
    /// --------------------------------------------------
    
    /// @dev Determine whether all approvals and signatures are in place for `makerToYield`.
    /// If `return[0]` is `false`, calling `vat.hope(proxy.address)` will set the MakerDAO approval.
    /// If `return[1]` is `false`, calling `makerToYieldWithSignature` will set the approvals.
    /// If `return[2]` is `false`, `makerToYieldWithSignature` must be called with a controller signature.
    /// If `return` is `(true, true)`, `makerToYield` won't fail because of missing approvals or signatures.
    function makerToYieldCheck(IPool pool) public view returns (bool, bool, bool) {
        bool hope = vat.can(msg.sender, address(this)) == 1;
        bool approvals = true;
        approvals = approvals && pool.fyDai().allowance(address(this), address(pool)) >= type(uint112).max;
        approvals = approvals && weth.allowance(address(this), treasury) == type(uint256).max;
        approvals = approvals && vat.can(address(this), address(wethJoin)) == 1;
        approvals = approvals && dai.allowance(address(this), address(daiJoin)) == type(uint256).max;

        bool controllerSig = controller.delegated(msg.sender, address(this));
        return (hope, approvals, controllerSig);
    }

    /// @dev Transfer debt and collateral from MakerDAO to Yield
    /// Needs vat.hope(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore fyDai series to borrow)
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    function makerToYieldWithSignature(IPool pool, uint256 wethAmount, uint256 daiAmount, bytes memory controllerSig) public {
        // Allow pool to take fyDai for trading
        if (pool.fyDai().allowance(address(this), address(pool)) < type(uint112).max) pool.fyDai().approve(address(pool), type(uint256).max);

        // Allow treasury to take weth for posting
        if (weth.allowance(address(this), treasury) < type(uint256).max) weth.approve(treasury, type(uint256).max);

        // Allow wethJoin to move weth out of vat for this proxy
        if (vat.can(address(this), address(wethJoin)) != 1) vat.hope(address(wethJoin));

        // Allow daiJoin to take Dai for paying debt
        if (dai.allowance(address(this), address(daiJoin)) < type(uint256).max) dai.approve(address(daiJoin), type(uint256).max);

        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        return makerToYield(pool, wethAmount, daiAmount);
    }

    /// @dev Determine whether all approvals and signatures are in place for `yieldToMaker`.
    /// If `return[0]` is `false`, calling `vat.hope(proxy.address)` will set the MakerDAO approval.
    /// If `return[1]` is `false`, calling `yieldToMakerWithSignature` will set the approvals.
    /// If `return[2]` is `false`, `yieldToMakerWithSignature` must be called with a controller signature.
    /// If `return` is `(true, true)`, `yieldToMaker` won't fail because of missing approvals or signatures.
    function yieldToMakerCheck(IPool pool) public view returns (bool, bool, bool) {
        bool hope = vat.can(msg.sender, address(this)) == 1;
        bool approvals = true;
        approvals = approvals && dai.allowance(address(this), treasury) == type(uint256).max;
        approvals = approvals && dai.allowance(address(this), address(pool)) == type(uint256).max;
        approvals = approvals && vat.can(address(this), address(daiJoin)) == 1;
        approvals = approvals && weth.allowance(address(this), address(wethJoin)) == type(uint256).max;

        bool controllerSig = controller.delegated(msg.sender, address(this));
        return (hope, approvals, controllerSig);
    }

    /// @dev Transfer debt and collateral from Yield to MakerDAO
    /// Needs vat.hope(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore fyDai series to migrate)
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    /// @param fyDaiAmount fyDai debt to move from Yield to MakerDAO.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    function yieldToMakerWithSignature(IPool pool, uint256 wethAmount, uint256 fyDaiAmount, bytes memory controllerSig) public {
        // Allow the Treasury to take dai for repaying
        if (dai.allowance(address(this), treasury) < type(uint256).max) dai.approve(treasury, type(uint256).max);

        // Allow the Pool to take dai for trading
        if (dai.allowance(address(this), address(pool)) < type(uint256).max) dai.approve(address(pool), type(uint256).max);

        // Allow daiJoin to move dai out of vat for this proxy
        if (vat.can(address(this), address(daiJoin)) != 1) vat.hope(address(daiJoin));

        // Allow wethJoin to take weth for collateralization
        if (weth.allowance(address(this), address(wethJoin)) < type(uint256).max) weth.approve(address(wethJoin), type(uint256).max);

        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        return yieldToMaker(pool, wethAmount, fyDaiAmount);
    }
}
