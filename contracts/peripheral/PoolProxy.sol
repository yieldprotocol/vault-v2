// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IWeth.sol";
import "../interfaces/IDai.sol";
import "../interfaces/IGemJoin.sol";
import "../interfaces/IDaiJoin.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IFYDai.sol";
import "../interfaces/IChai.sol";
import "../interfaces/IDelegable.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IController.sol";
import "../helpers/DecimalMath.sol";


library SafeCast {
    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= type(uint128).max,
            "YieldProxy: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Safe casting from uint256 to int256
    function toInt256(uint256 x) internal pure returns(int256) {
        require(
            x <= uint256(type(int256).max),
            "YieldProxy: Cast overflow"
        );
        return int256(x);
    }
}

contract PoolProxy is DecimalMath {
    using SafeCast for uint256;

    IVat public vat;
    IWeth public weth;
    IDai public dai;
    IGemJoin public wethJoin;
    IDaiJoin public daiJoin;
    IChai public chai;
    IController public controller;
    ITreasury public treasury;

    IPool[] public pools;
    mapping (address => bool) public poolsMap;

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";
    bool constant public MTY = true;
    bool constant public YTM = false;


    constructor(address controller_, IPool[] memory _pools) public {
        controller = IController(controller_);
        treasury = controller.treasury();

        weth = treasury.weth();
        dai = IDai(address(treasury.dai()));
        chai = treasury.chai();
        daiJoin = treasury.daiJoin();
        wethJoin = treasury.wethJoin();
        vat = treasury.vat();

        // for repaying debt
        dai.approve(address(treasury), uint(-1));

        // for posting to the controller
        chai.approve(address(treasury), uint(-1));
        weth.approve(address(treasury), uint(-1));

        // for converting DAI to CHAI
        dai.approve(address(chai), uint(-1));

        vat.hope(address(daiJoin));
        vat.hope(address(wethJoin));

        dai.approve(address(daiJoin), uint(-1));
        weth.approve(address(wethJoin), uint(-1));
        weth.approve(address(treasury), uint(-1));

        // allow all the pools to pull FYDai/dai from us for LPing
        for (uint i = 0 ; i < _pools.length; i++) {
            dai.approve(address(_pools[i]), uint(-1));
            _pools[i].fyDai().approve(address(_pools[i]), uint(-1));
            poolsMap[address(_pools[i])]= true;
        }

        pools = _pools;
    }

    /// @dev Unpack r, s and v from a `bytes` signature
    function unpack(bytes memory signature) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
    }

    function authorizeForAdding(bytes memory daiSig, bytes memory controllerSig) public {
        bytes32 r;
        bytes32 s;
        uint8 v;

        (r, s, v) = unpack(daiSig);
        dai.permit(msg.sender, address(this), dai.nonces(msg.sender), uint(-1), true, v, r, s);

        (r, s, v) = unpack(controllerSig);
        
        try controller.addDelegateBySignature(msg.sender, address(this), uint(-1), v, r, s) { }
        catch Error(string memory) {
            // We just want to silence the revert on adding a delegate again, but we are also silencing invalid or expired permits
            // We check delegation, and if it doesn't exist revert.
            require(controller.delegated(msg.sender, address(this)), "PoolProxy: Invalid controller signature");
        }
    }

    function authorizeForRemoving(IPool pool, bytes memory controllerSig, bytes memory poolSig) public {
        onlyKnownPool(pool);

        bytes32 r;
        bytes32 s;
        uint8 v;

        (r, s, v) = unpack(controllerSig);
        try controller.addDelegateBySignature(msg.sender, address(this), uint(-1), v, r, s) { }
        catch Error(string memory) {
            // We just want to silence the revert on adding a delegate again, but we are also silencing invalid or expired permits
            // We check delegation, and if it doesn't exist revert.
            require(controller.delegated(msg.sender, address(this)), "PoolProxy: Invalid controller signature");
        }

        (r, s, v) = unpack(poolSig);
        try pool.addDelegateBySignature(msg.sender, address(this), uint(-1), v, r, s) { }
        catch Error(string memory) {
            // We just want to silence the revert on adding a delegate again, but we are also silencing invalid or expired permits
            // We check delegation, and if it doesn't exist revert.
            require(pool.delegated(msg.sender, address(this)), "PoolProxy: Invalid controller signature");
        }
    }

    /// @dev Mints liquidity with provided Dai by borrowing fyDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxFYDai maximum amount of fyDai to be borrowed to mint liquidity.
    /// @param daiSig packed signature for permit of dai transfers to this proxy.
    /// @param controllerSig packed signature for delegation of this proxy in the controller.
    /// @return The amount of liquidity tokens minted.  
    function addLiquidityWithSignature(
        IPool pool,
        uint256 daiUsed,
        uint256 maxFYDai,
        bytes memory daiSig,
        bytes memory controllerSig
    ) external returns (uint256) {
        onlyKnownPool(pool);
        authorizeForAdding(daiSig, controllerSig);
        return addLiquidity(pool, daiUsed, maxFYDai);
    }

    /// @dev Burns tokens and sells Dai proceedings for fyDai. Pays as much debt as possible, then sells back any remaining fyDai for Dai. Then returns all Dai, and all unlocked Chai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)` and `pool.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)` <-- It actually doesn't.
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumDaiPrice minimum fyDai/Dai price to be accepted when internally selling Dai.
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    /// @param controllerSig packed signature for delegation of this proxy in the controller.
    /// @param poolSig packed signature for delegation of this proxy in a pool.
    function removeLiquidityEarlyDaiPoolWithSignature(
        IPool pool,
        uint256 poolTokens,
        uint256 minimumDaiPrice,
        uint256 minimumFYDaiPrice,
        bytes memory controllerSig,
        bytes memory poolSig
    ) public {
        onlyKnownPool(pool);
        authorizeForRemoving(pool, controllerSig, poolSig);
        removeLiquidityEarlyDaiPool(pool, poolTokens, minimumDaiPrice, minimumFYDaiPrice);
    }

    /// @dev Burns tokens and repays debt with proceedings. Sells any excess fyDai for Dai, then returns all Dai, and all unlocked Chai.
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    /// @param controllerSig packed signature for delegation of this proxy in the controller.
    /// @param poolSig packed signature for delegation of this proxy in a pool.
    function removeLiquidityEarlyDaiFixedWithSignature(
        IPool pool,
        uint256 poolTokens,
        uint256 minimumFYDaiPrice,
        bytes memory controllerSig,
        bytes memory poolSig
    ) public {
        onlyKnownPool(pool);
        authorizeForRemoving(pool, controllerSig, poolSig);
        removeLiquidityEarlyDaiFixed(pool, poolTokens, minimumFYDaiPrice);
    }

    /// @dev Burns tokens and repays fyDai debt after Maturity.
    /// @param poolTokens amount of pool tokens to burn.
    /// @param controllerSig packed signature for delegation of this proxy in the controller.
    /// @param poolSig packed signature for delegation of this proxy in a pool.
    function removeLiquidityMatureWithSignature(
        IPool pool,
        uint256 poolTokens,
        bytes memory controllerSig,
        bytes memory poolSig
    ) external {
        onlyKnownPool(pool);
        authorizeForRemoving(pool, controllerSig, poolSig);
        removeLiquidityMature(pool, poolTokens);
    }

    /// @dev Mints liquidity with provided Dai by borrowing fyDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxFYDai maximum amount of fyDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(IPool pool, uint256 daiUsed, uint256 maxFYDai) public returns (uint256) {
        onlyKnownPool(pool);
        IFYDai fyDai = pool.fyDai();
        require(fyDai.isMature() != true, "YieldProxy: Only before maturity");
        require(dai.transferFrom(msg.sender, address(this), daiUsed), "YieldProxy: Transfer Failed");

        // calculate needed fyDai
        uint256 daiReserves = dai.balanceOf(address(pool));
        uint256 fyDaiReserves = fyDai.balanceOf(address(pool));
        uint256 daiToAdd = daiUsed.mul(daiReserves).div(fyDaiReserves.add(daiReserves));
        uint256 daiToConvert = daiUsed.sub(daiToAdd);
        require(
            daiToConvert <= maxFYDai,
            "YieldProxy: maxFYDai exceeded"
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
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)` and `pool.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumDaiPrice minimum fyDai/Dai price to be accepted when internally selling Dai.
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    function removeLiquidityEarlyDaiPool(IPool pool, uint256 poolTokens, uint256 minimumDaiPrice, uint256 minimumFYDaiPrice) public {
        onlyKnownPool(pool);

        IFYDai fyDai = pool.fyDai();
        uint256 maturity = fyDai.maturity();
        (uint256 daiObtained, uint256 fyDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);

        // Exchange Dai for fyDai to pay as much debt as possible
        uint256 fyDaiBought = pool.sellDai(address(this), address(this), daiObtained.toUint128());
        require(
            fyDaiBought >= muld(daiObtained, minimumDaiPrice),
            "YieldProxy: minimumDaiPrice not reached"
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
                "YieldProxy: minimumFYDaiPrice not reached"
            );
        }
        withdrawAssets();
    }

    /// @dev Burns tokens and repays debt with proceedings. Sells any excess fyDai for Dai, then returns all Dai, and if there is no debt in the Controller, all posted Chai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)` and `pool.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumFYDaiPrice minimum Dai/fyDai price to be accepted when internally selling fyDai.
    function removeLiquidityEarlyDaiFixed(IPool pool, uint256 poolTokens, uint256 minimumFYDaiPrice) public {
        onlyKnownPool(pool);
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
                "YieldProxy: minimumFYDaiPrice not reached"
            );
        }
        withdrawAssets();
    }

    /// @dev Burns tokens and repays fyDai debt after Maturity. 
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn.
    function removeLiquidityMature(IPool pool, uint256 poolTokens) public {
        onlyKnownPool(pool);
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
        require (posted >= locked, "YieldProxy: Undercollateralized");
        controller.withdraw(CHAI, msg.sender, address(this), posted - locked);
        chai.exit(address(this), chai.balanceOf(address(this)));
        require(dai.transfer(msg.sender, dai.balanceOf(address(this))), "YieldProxy: Dai Transfer Failed");
    }

    function onlyKnownPool(IPool pool) private view {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
    }
}
