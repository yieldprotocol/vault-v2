// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IDai.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IFYDai.sol";
import "../interfaces/IChai.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IController.sol";
import "../helpers/DecimalMath.sol";
import "../helpers/SafeCast.sol";
import "../helpers/YieldAuth.sol";


contract PoolProxy is DecimalMath {
    using SafeCast for uint256;
    using YieldAuth for IController;
    using YieldAuth for IDai;
    using YieldAuth for IFYDai;
    using YieldAuth for IPool;

    IDai public immutable dai;
    IChai public immutable chai;
    IController public immutable controller;
    address immutable treasury;

    bytes32 public constant CHAI = "CHAI";

    constructor(IController _controller) public {
        ITreasury _treasury = _controller.treasury();
        dai = _treasury.dai();
        chai = _treasury.chai();
        treasury = address(_treasury);
        controller = _controller;
    }

    /// @dev Mints liquidity with provided Dai by borrowing fyDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(poolProxy)` or with `addLiquidityWithSignature`.
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)` or with `addLiquidityWithSignature`.
    /// Caller must have called `addLiquidityWithSignature` at least once before to set proxy approvals.
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxFYDai maximum amount of fyDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(IPool pool, uint256 daiUsed, uint256 maxFYDai) public returns (uint256) {
        IFYDai fyDai = pool.fyDai();
        require(fyDai.isMature() != true, "PoolProxy: Only before maturity");
        require(dai.transferFrom(msg.sender, address(this), daiUsed), "PoolProxy: Transfer Failed");

        // calculate needed fyDai
        uint256 daiReserves = dai.balanceOf(address(pool));
        uint256 fyDaiReserves = fyDai.balanceOf(address(pool));
        uint256 daiToAdd = daiUsed.mul(daiReserves).div(fyDaiReserves.add(daiReserves));
        uint256 daiToConvert = daiUsed.sub(daiToAdd);
        require(
            daiToConvert <= maxFYDai,
            "PoolProxy: maxFYDai exceeded"
        ); // 1 Dai == 1 fyDai

        // convert dai to chai and borrow needed fyDai
        chai.join(address(this), daiToConvert);
        // look at the balance of chai in dai to avoid rounding issues
        uint256 toBorrow = chai.dai(address(this));
        controller.post(CHAI, address(this), msg.sender, chai.balanceOf(address(this)));
        controller.borrow(CHAI, fyDai.maturity(), msg.sender, address(this), toBorrow);
        
        // mint liquidity tokens
        return pool.mint(address(this), msg.sender, daiToAdd);
    }

    /// @dev Burns tokens and sells Dai proceedings for fyDai. Pays as much debt as possible, then sells back any remaining fyDai for Dai. Then returns all Dai, and if there is no debt in the Controller, all posted Chai.
    /// Caller must have approved the proxy using`controller.addDelegate(poolProxy)` and `pool.addDelegate(poolProxy)` or with `removeLiquidityEarlyDaiPoolWithSignature`
    /// Caller must have called `removeLiquidityEarlyDaiPoolWithSignature` at least once before to set proxy approvals.
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumDaiPrice minimum fyDai/Dai price to be accepted when internally selling Dai.
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    function removeLiquidityEarlyDaiPool(IPool pool, uint256 poolTokens, uint256 minimumDaiPrice, uint256 minimumFYDaiPrice) public {

        IFYDai fyDai = pool.fyDai();
        uint256 maturity = fyDai.maturity();

        (uint256 daiObtained, uint256 fyDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);

        // Exchange Dai for fyDai to pay as much debt as possible
        uint256 fyDaiBought = pool.sellDai(address(this), address(this), daiObtained.toUint128());
        require(
            fyDaiBought >= muld(daiObtained, minimumDaiPrice),
            "PoolProxy: minimumDaiPrice not reached"
        );
        fyDaiObtained = fyDaiObtained.add(fyDaiBought);
        
        uint256 fyDaiUsed;
        if (fyDaiObtained > 0 && controller.debtFYDai(CHAI, maturity, msg.sender) > 0) {
            fyDaiUsed = controller.repayFYDai(CHAI, maturity, address(this), msg.sender, fyDaiObtained);
        }
        uint256 fyDaiRemaining = fyDaiObtained.sub(fyDaiUsed);

        if (fyDaiRemaining > 0) {// There is fyDai left, so exchange it for Dai to withdraw only Dai and Chai
            require(
                pool.sellFYDai(address(this), address(this), uint128(fyDaiRemaining)) >= muld(fyDaiRemaining, minimumFYDaiPrice),
                "PoolProxy: minimumFYDaiPrice not reached"
            );
        }
        withdrawAssets();
    }

    /// @dev Burns tokens and repays debt with proceedings. Sells any excess fyDai for Dai, then returns all Dai, and if there is no debt in the Controller, all posted Chai.
    /// Caller must have approved the proxy using`controller.addDelegate(poolProxy)` and `pool.addDelegate(poolProxy)` or with `removeLiquidityEarlyDaiFixedWithSignature`
    /// Caller must have called `removeLiquidityEarlyDaiFixedWithSignature` at least once before to set proxy approvals.
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    function removeLiquidityEarlyDaiFixed(IPool pool, uint256 poolTokens, uint256 minimumFYDaiPrice) public {

        IFYDai fyDai = pool.fyDai();
        uint256 maturity = fyDai.maturity();

        (uint256 daiObtained, uint256 fyDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);
        uint256 fyDaiUsed;
        if (fyDaiObtained > 0 && controller.debtFYDai(CHAI, maturity, msg.sender) > 0) {
            fyDaiUsed = controller.repayFYDai(CHAI, maturity, address(this), msg.sender, fyDaiObtained);
        }

        uint256 fyDaiRemaining = fyDaiObtained.sub(fyDaiUsed);
        if (fyDaiRemaining == 0) { // We used all the fyDai, so probably there is debt left, so pay with Dai
            if (daiObtained > 0 && controller.debtFYDai(CHAI, maturity, msg.sender) > 0) {
                controller.repayDai(CHAI, maturity, address(this), msg.sender, daiObtained);
            }
        } else { // Exchange remaining fyDai for Dai to withdraw only Dai and Chai
            require(
                pool.sellFYDai(address(this), address(this), uint128(fyDaiRemaining)) >= muld(fyDaiRemaining, minimumFYDaiPrice),
                "PoolProxy: minimumFYDaiPrice not reached"
            );
        }
        withdrawAssets();
    }

    /// @dev Burns tokens and repays fyDai debt after Maturity. 
    /// Caller must have approved the proxy using`controller.addDelegate(poolProxy)` or `removeLiquidityEarlyDaiFixedWithSignature`
    /// Caller must have called `removeLiquidityEarlyDaiFixedWithSignature` at least once before to set proxy approvals.
    /// @param poolTokens amount of pool tokens to burn.
    function removeLiquidityMature(IPool pool, uint256 poolTokens) public {

        IFYDai fyDai = pool.fyDai();
        uint256 maturity = fyDai.maturity();

        (uint256 daiObtained, uint256 fyDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);
        if (fyDaiObtained > 0) {
            daiObtained = daiObtained.add(fyDai.redeem(address(this), address(this), fyDaiObtained));
        }
        
        // Repay debt
        if (daiObtained > 0 && controller.debtFYDai(CHAI, maturity, msg.sender) > 0) {
            controller.repayDai(CHAI, maturity, address(this), msg.sender, daiObtained);
        }
        withdrawAssets();
    }

    /// @dev Return to caller all posted chai if there is no debt, converted to dai, plus any dai remaining in the contract.
    function withdrawAssets() internal {
        uint256 posted = controller.posted(CHAI, msg.sender);
        uint256 locked = controller.locked(CHAI, msg.sender);
        require (posted >= locked, "PoolProxy: Undercollateralized");
        controller.withdraw(CHAI, msg.sender, address(this), posted - locked);
        chai.exit(address(this), chai.balanceOf(address(this)));
        require(dai.transfer(msg.sender, dai.balanceOf(address(this))), "PoolProxy: Dai Transfer Failed");
    }

    /// --------------------------------------------------
    /// Signature method wrappers
    /// --------------------------------------------------

    /// @dev Determine whether all approvals and signatures are in place for `addLiquidity`.
    /// If `return[0]` is `false`, calling `addLiquidityWithSignature` will set the proxy approvals.
    /// If `return[1]` is `false`, `addLiquidityWithSignature` must be called with a dai permit signature.
    /// If `return[2]` is `false`, `addLiquidityWithSignature` must be called with a controller signature.
    /// If `return` is `(true, true, true)`, `addLiquidity` won't fail because of missing approvals or signatures.
    function addLiquidityCheck(IPool pool) public view returns (bool, bool, bool) {
        bool approvals = true;
        approvals = approvals && chai.allowance(address(this), treasury) == type(uint256).max;
        approvals = approvals && dai.allowance(address(this), address(chai)) == type(uint256).max;
        approvals = approvals && dai.allowance(address(this), address(pool)) == type(uint256).max;
        approvals = approvals && pool.fyDai().allowance(address(this), address(pool)) >= type(uint112).max;
        bool daiSig = dai.allowance(msg.sender, address(this)) == type(uint256).max;
        bool controllerSig = controller.delegated(msg.sender, address(this));
        return (approvals, daiSig, controllerSig);
    }

    /// @dev Mints liquidity with provided Dai by borrowing fyDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(poolProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxFYDai maximum amount of fyDai to be borrowed to mint liquidity.
    /// @param daiSig packed signature for permit of dai transfers to this proxy. Ignored if '0x'.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    /// @return The amount of liquidity tokens minted.  
    function addLiquidityWithSignature(
        IPool pool,
        uint256 daiUsed,
        uint256 maxFYDai,
        bytes memory daiSig,
        bytes memory controllerSig
    ) external returns (uint256) {
        // Allow the Treasury to take chai when posting
        if (chai.allowance(address(this), treasury) < type(uint256).max) chai.approve(treasury, type(uint256).max);

        // Allow Chai to take dai for wrapping
        if (dai.allowance(address(this), address(chai)) < type(uint256).max) dai.approve(address(chai), type(uint256).max);

        // Allow pool to take dai for minting
        if (dai.allowance(address(this), address(pool)) < type(uint256).max) dai.approve(address(pool), type(uint256).max);

        // Allow pool to take fyDai for minting
        if (pool.fyDai().allowance(address(this), address(pool)) < type(uint112).max) pool.fyDai().approve(address(pool), type(uint256).max);

        if (daiSig.length > 0) dai.permitPackedDai(address(this), daiSig);
        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        return addLiquidity(pool, daiUsed, maxFYDai);
    }

    /// @dev Determine whether all approvals and signatures are in place for `removeLiquidityEarlyDaiPool`.
    /// If `return[0]` is `false`, calling `removeLiquidityEarlyDaiPoolWithSignature` will set the proxy approvals.
    /// If `return[1]` is `false`, `removeLiquidityEarlyDaiPoolWithSignature` must be called with a controller signature.
    /// If `return[2]` is `false`, `removeLiquidityEarlyDaiPoolWithSignature` must be called with a pool signature.
    /// If `return` is `(true, true, true)`, `removeLiquidityEarlyDaiPool` won't fail because of missing approvals or signatures.
    function removeLiquidityEarlyDaiPoolCheck(IPool pool) public view returns (bool, bool, bool) {
        bool approvals = true;
        approvals = approvals && dai.allowance(address(this), address(pool)) == type(uint256).max;
        approvals = approvals && pool.fyDai().allowance(address(this), address(pool)) >= type(uint112).max;
        bool controllerSig = controller.delegated(msg.sender, address(this));
        bool poolSig = pool.delegated(msg.sender, address(this));
        return (approvals, controllerSig, poolSig);
    }

    /// @dev Burns tokens and sells Dai proceedings for fyDai. Pays as much debt as possible, then sells back any remaining fyDai for Dai. Then returns all Dai, and all unlocked Chai.
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumDaiPrice minimum fyDai/Dai price to be accepted when internally selling Dai.
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    /// @param poolSig packed signature for delegation of this proxy in a pool. Ignored if '0x'.
    function removeLiquidityEarlyDaiPoolWithSignature(
        IPool pool,
        uint256 poolTokens,
        uint256 minimumDaiPrice,
        uint256 minimumFYDaiPrice,
        bytes memory controllerSig,
        bytes memory poolSig
    ) public {
        // Allow pool to take dai for trading
        if (dai.allowance(address(this), address(pool)) < type(uint256).max) dai.approve(address(pool), type(uint256).max);

        // Allow pool to take fyDai for trading
        if (pool.fyDai().allowance(address(this), address(pool)) < type(uint112).max) pool.fyDai().approve(address(pool), type(uint256).max);

        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        if (poolSig.length > 0) pool.addDelegatePacked(poolSig);
        removeLiquidityEarlyDaiPool(pool, poolTokens, minimumDaiPrice, minimumFYDaiPrice);
    }

    /// @dev Determine whether all approvals and signatures are in place for `removeLiquidityEarlyDaiFixed`.
    /// If `return[0]` is `false`, calling `removeLiquidityEarlyDaiFixedWithSignature` will set the proxy approvals.
    /// If `return[1]` is `false`, `removeLiquidityEarlyDaiFixedWithSignature` must be called with a controller signature.
    /// If `return[2]` is `false`, `removeLiquidityEarlyDaiFixedWithSignature` must be called with a pool signature.
    /// If `return` is `(true, true, true)`, `removeLiquidityEarlyDaiFixed` won't fail because of missing approvals or signatures.
    function removeLiquidityEarlyDaiFixedCheck(IPool pool) public view returns (bool, bool, bool) {
        bool approvals = true;
        approvals = approvals && dai.allowance(address(this), address(pool)) == type(uint256).max;
        approvals = approvals && pool.fyDai().allowance(address(this), address(pool)) >= type(uint112).max;
        bool controllerSig = controller.delegated(msg.sender, address(this));
        bool poolSig = pool.delegated(msg.sender, address(this));
        return (approvals, controllerSig, poolSig);
    }

    /// @dev Burns tokens and repays debt with proceedings. Sells any excess fyDai for Dai, then returns all Dai, and all unlocked Chai.
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    /// @param poolSig packed signature for delegation of this proxy in a pool. Ignored if '0x'.
    function removeLiquidityEarlyDaiFixedWithSignature(
        IPool pool,
        uint256 poolTokens,
        uint256 minimumFYDaiPrice,
        bytes memory controllerSig,
        bytes memory poolSig
    ) public {
        // Allow the Treasury to take dai for repaying
        if (dai.allowance(address(this), treasury) < type(uint256).max) dai.approve(treasury, type(uint256).max);

        // Allow pool to take fyDai for trading
        if (pool.fyDai().allowance(address(this), address(pool)) < type(uint112).max) pool.fyDai().approve(address(pool), type(uint256).max);

        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        if (poolSig.length > 0) pool.addDelegatePacked(poolSig);
        removeLiquidityEarlyDaiFixed(pool, poolTokens, minimumFYDaiPrice);
    }

    /// @dev Determine whether all approvals and signatures are in place for `removeLiquidityMature`.
    /// If `return[0]` is `false`, calling `removeLiquidityMatureCheck` will set the proxy approvals.
    /// If `return[1]` is `false`, `removeLiquidityMatureCheck` must be called with a controller signature.
    /// If `return[2]` is `false`, `removeLiquidityMatureCheck` must be called with a pool signature.
    /// If `return` is `(true, true, true)`, `removeLiquidityMature` won't fail because of missing approvals or signatures.
    function removeLiquidityMatureCheck(IPool pool) public view returns (bool, bool, bool) {
        bool approvals = dai.allowance(address(this), treasury) == type(uint256).max;
        bool controllerSig = controller.delegated(msg.sender, address(this));
        bool poolSig = pool.delegated(msg.sender, address(this));
        return (approvals, controllerSig, poolSig);
    }

    /// @dev Burns tokens and repays fyDai debt after Maturity.
    /// @param poolTokens amount of pool tokens to burn.
    /// @param controllerSig packed signature for delegation of this proxy in the controller. Ignored if '0x'.
    /// @param poolSig packed signature for delegation of this proxy in a pool. Ignored if '0x'.
    function removeLiquidityMatureWithSignature(
        IPool pool,
        uint256 poolTokens,
        bytes memory controllerSig,
        bytes memory poolSig
    ) external {
        // Allow the Treasury to take dai for repaying
        if (dai.allowance(address(this), treasury) < type(uint256).max) dai.approve(treasury, type(uint256).max);

        if (controllerSig.length > 0) controller.addDelegatePacked(controllerSig);
        if (poolSig.length > 0) pool.addDelegatePacked(poolSig);
        removeLiquidityMature(pool, poolTokens);
    }
}
