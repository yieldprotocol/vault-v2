// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IController.sol";
import "../interfaces/IWeth.sol";
import "../interfaces/IDai.sol";
import "../interfaces/IGemJoin.sol";
import "../interfaces/IDaiJoin.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IEDai.sol";
import "../interfaces/IChai.sol";
import "../interfaces/IFlashMinter.sol";
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

contract YieldProxy is DecimalMath, IFlashMinter {
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

        // allow all the pools to pull EDai/dai from us for LPing
        for (uint i = 0 ; i < _pools.length; i++) {
            dai.approve(address(_pools[i]), uint(-1));
            _pools[i].eDai().approve(address(_pools[i]), uint(-1));
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

    /// @dev Performs the initial onboarding of the user. It `permit`'s DAI to be used by the proxy, and adds the proxy as a delegate in the controller
    function onboard(address from, bytes memory daiSignature, bytes memory controllerSig) external {
        bytes32 r;
        bytes32 s;
        uint8 v;

        (r, s, v) = unpack(daiSignature);
        dai.permit(from, address(this), dai.nonces(from), uint(-1), true, v, r, s);

        (r, s, v) = unpack(controllerSig);
        controller.addDelegateBySignature(from, address(this), uint(-1), v, r, s);
    }

    /// @dev Given a pool and 3 signatures, it `permit`'s dai and eDai for that pool and adds it as a delegate
    function authorizePool(IPool pool, address from, bytes memory daiSig, bytes memory eDaiSig, bytes memory poolSig) public {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        bytes32 r;
        bytes32 s;
        uint8 v;

        (r, s, v) = unpack(daiSig);
        dai.permit(from, address(pool), dai.nonces(from), uint(-1), true, v, r, s);

        (r, s, v) = unpack(eDaiSig);
        pool.eDai().permit(from, address(this), uint(-1), uint(-1), v, r, s);

        (r, s, v) = unpack(poolSig);
        pool.addDelegateBySignature(from, address(this), uint(-1), v, r, s);
    }

    /// @dev The WETH9 contract will send ether to YieldProxy on `weth.withdraw` using this function.
    receive() external payable { }

    /// @dev Users use `post` in YieldProxy to post ETH to the Controller (amount = msg.value), which will be converted to Weth here.
    /// @param to Yield Vault to deposit collateral in.
    function post(address to)
        public payable {
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

    /// @dev Mints liquidity with provided Dai by borrowing eDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxEDai maximum amount of eDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(IPool pool, uint256 daiUsed, uint256 maxEDai) external returns (uint256) {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        IEDai eDai = pool.eDai();
        require(eDai.isMature() != true, "YieldProxy: Only before maturity");
        require(dai.transferFrom(msg.sender, address(this), daiUsed), "YieldProxy: Transfer Failed");

        // calculate needed eDai
        uint256 daiReserves = dai.balanceOf(address(pool));
        uint256 eDaiReserves = eDai.balanceOf(address(pool));
        uint256 daiToAdd = daiUsed.mul(daiReserves).div(eDaiReserves.add(daiReserves));
        uint256 daiToConvert = daiUsed.sub(daiToAdd);
        require(
            daiToConvert <= maxEDai,
            "YieldProxy: maxEDai exceeded"
        ); // 1 Dai == 1 eDai

        // convert dai to chai and borrow needed eDai
        chai.join(address(this), daiToConvert);
        // look at the balance of chai in dai to avoid rounding issues
        uint256 toBorrow = chai.dai(address(this));
        controller.post(CHAI, address(this), msg.sender, chai.balanceOf(address(this)));
        controller.borrow(CHAI, eDai.maturity(), msg.sender, address(this), toBorrow);
        
        // mint liquidity tokens
        return pool.mint(address(this), msg.sender, daiToAdd);
    }

    /// @dev Burns tokens and sells Dai proceedings for eDai. Pays as much debt as possible, then sells back any remaining eDai for Dai. Then returns all Dai, and if there is no debt in the Controller, all posted Chai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)` and `pool.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumDaiPrice minimum eDai/Dai price to be accepted when internally selling Dai.
    /// @param minimumEDaiPrice minimum Dai/eDai price to be accepted when internally selling eDai.
    function removeLiquidityEarlyDaiPool(IPool pool, uint256 poolTokens, uint256 minimumDaiPrice, uint256 minimumEDaiPrice) external {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        IEDai eDai = pool.eDai();
        uint256 maturity = eDai.maturity();
        (uint256 daiObtained, uint256 eDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);

        // Exchange Dai for eDai to pay as much debt as possible
        uint256 eDaiBought = pool.sellDai(address(this), address(this), daiObtained.toUint128());
        require(
            eDaiBought >= muld(daiObtained, minimumDaiPrice),
            "YieldProxy: minimumDaiPrice not reached"
        );
        eDaiObtained = eDaiObtained.add(eDaiBought);
        
        uint256 eDaiUsed;
        if (eDaiObtained > 0 && controller.debtEDai(CHAI, maturity, msg.sender) > 0) {
            eDaiUsed = controller.repayEDai(CHAI, maturity, address(this), msg.sender, eDaiObtained);
        }
        uint256 eDaiRemaining = eDaiObtained.sub(eDaiUsed);

        if (eDaiRemaining > 0) {// There is eDai left, so exchange it for Dai to withdraw only Dai and Chai
            require(
                pool.sellEDai(address(this), address(this), uint128(eDaiRemaining)) >= muld(eDaiRemaining, minimumEDaiPrice),
                "YieldProxy: minimumEDaiPrice not reached"
            );
        }
        withdrawAssets(eDai);
    }

    /// @dev Burns tokens and repays debt with proceedings. Sells any excess eDai for Dai, then returns all Dai, and if there is no debt in the Controller, all posted Chai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)` and `pool.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumEDaiPrice minimum Dai/eDai price to be accepted when internally selling eDai.
    function removeLiquidityEarlyDaiFixed(IPool pool, uint256 poolTokens, uint256 minimumEDaiPrice) external {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        IEDai eDai = pool.eDai();
        uint256 maturity = eDai.maturity();
        (uint256 daiObtained, uint256 eDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);

        uint256 eDaiUsed;
        if (eDaiObtained > 0 && controller.debtEDai(CHAI, maturity, msg.sender) > 0) {
            eDaiUsed = controller.repayEDai(CHAI, maturity, address(this), msg.sender, eDaiObtained);
        }

        uint256 eDaiRemaining = eDaiObtained.sub(eDaiUsed);
        if (eDaiRemaining == 0) { // We used all the eDai, so probably there is debt left, so pay with Dai
            if (daiObtained > 0 && controller.debtEDai(CHAI, maturity, msg.sender) > 0) {
                controller.repayDai(CHAI, maturity, address(this), msg.sender, daiObtained);
            }
        } else { // Exchange remaining eDai for Dai to withdraw only Dai and Chai
            require(
                pool.sellEDai(address(this), address(this), uint128(eDaiRemaining)) >= muld(eDaiRemaining, minimumEDaiPrice),
                "YieldProxy: minimumEDaiPrice not reached"
            );
        }
        withdrawAssets(eDai);
    }

    /// @dev Burns tokens and repays eDai debt after Maturity. 
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn.
    function removeLiquidityMature(IPool pool, uint256 poolTokens) external {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        IEDai eDai = pool.eDai();
        uint256 maturity = eDai.maturity();
        (uint256 daiObtained, uint256 eDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);
        if (eDaiObtained > 0) {
            daiObtained = daiObtained.add(eDai.redeem(address(this), address(this), eDaiObtained));
        }
        
        // Repay debt
        if (daiObtained > 0 && controller.debtEDai(CHAI, maturity, msg.sender) > 0) {
            controller.repayDai(CHAI, maturity, address(this), msg.sender, daiObtained);
        }
        withdrawAssets(eDai);
    }

    /// @dev Return to caller all posted chai if there is no debt, converted to dai, plus any dai remaining in the contract.
    function withdrawAssets(IEDai eDai) internal {
        if (controller.debtEDai(CHAI, eDai.maturity(), msg.sender) == 0) {
            controller.withdraw(CHAI, msg.sender, address(this), controller.posted(CHAI, msg.sender));
            chai.exit(address(this), chai.balanceOf(address(this)));
        }
        require(dai.transfer(msg.sender, dai.balanceOf(address(this))), "YieldProxy: Dai Transfer Failed");
    }

    /// @dev Borrow eDai from Controller and sell it immediately for Dai, for a maximum eDai debt.
    /// Must have approved the operator with `controller.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param maximumEDai Maximum amount of EDai to borrow.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    function borrowDaiForMaximumEDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 maximumEDai,
        uint256 daiToBorrow
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        uint256 eDaiToBorrow = pool.buyDaiPreview(daiToBorrow.toUint128());
        require (eDaiToBorrow <= maximumEDai, "YieldProxy: Too much eDai required");

        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), eDaiToBorrow);
        pool.buyDai(address(this), to, daiToBorrow.toUint128());

        return eDaiToBorrow;
    }

    /// @dev Borrow eDai from Controller and sell it immediately for Dai, if a minimum amount of Dai can be obtained such.
    /// Must have approved the operator with `controller.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to sent the resulting Dai to.
    /// @param eDaiToBorrow Amount of eDai to borrow.
    /// @param minimumDaiToBorrow Minimum amount of Dai that should be borrowed.
    function borrowMinimumDaiForEDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 eDaiToBorrow,
        uint256 minimumDaiToBorrow
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), eDaiToBorrow);
        uint256 boughtDai = pool.sellEDai(address(this), to, eDaiToBorrow.toUint128());
        require (boughtDai >= minimumDaiToBorrow, "YieldProxy: Not enough Dai obtained");

        return boughtDai;
    }


    /// @dev Repay an amount of eDai debt in Controller using Dai exchanged for eDai at pool rates, up to a maximum amount of Dai spent.
    /// Must have approved the operator with `pool.addDelegate(yieldProxy.address)`.
    /// If `eDaiRepayment` exceeds the existing debt, only the necessary eDai will be used.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay eDai debt for.
    /// @param eDaiRepayment Amount of eDai debt to repay.
    /// @param maximumRepaymentInDai Maximum amount of Dai that should be spent on the repayment.
    function repayEDaiDebtForMaximumDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 eDaiRepayment,
        uint256 maximumRepaymentInDai
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        uint256 eDaiDebt = controller.debtEDai(collateral, maturity, to);
        uint256 eDaiToUse = eDaiDebt < eDaiRepayment ? eDaiDebt : eDaiRepayment; // Use no more eDai than debt
        uint256 repaymentInDai = pool.buyEDai(msg.sender, address(this), eDaiToUse.toUint128());
        require (repaymentInDai <= maximumRepaymentInDai, "YieldProxy: Too much Dai required");
        controller.repayEDai(collateral, maturity, address(this), to, eDaiToUse);

        return repaymentInDai;
    }

    /// @dev Repay an amount of eDai debt in Controller using a given amount of Dai exchanged for eDai at pool rates, with a minimum of eDai debt required to be paid.
    /// Must have approved the operator with `pool.addDelegate(yieldProxy.address)`.
    /// If `repaymentInDai` exceeds the existing debt, only the necessary Dai will be used.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay eDai debt for.
    /// @param minimumEDaiRepayment Minimum amount of eDai debt to repay.
    /// @param repaymentInDai Exact amount of Dai that should be spent on the repayment.
    function repayMinimumEDaiDebtForDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 minimumEDaiRepayment,
        uint256 repaymentInDai
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        uint256 eDaiRepayment = pool.sellDaiPreview(repaymentInDai.toUint128());
        uint256 eDaiDebt = controller.debtEDai(collateral, maturity, to);
        if(eDaiRepayment <= eDaiDebt) { // Sell no more Dai than needed to cancel all the debt
            pool.sellDai(msg.sender, address(this), repaymentInDai.toUint128());
        } else { // If we have too much Dai, then don't sell it all and buy the exact amount of eDai needed instead.
            pool.buyEDai(msg.sender, address(this), eDaiDebt.toUint128());
            eDaiRepayment = eDaiDebt;
        }
        require (eDaiRepayment >= minimumEDaiRepayment, "YieldProxy: Not enough eDai debt repaid");
        controller.repayEDai(collateral, maturity, address(this), to, eDaiRepayment);

        return eDaiRepayment;
    }

    /// @dev Sell Dai for eDai
    /// @param to Wallet receiving the eDai being bought
    /// @param daiIn Amount of dai being sold
    /// @param minEDaiOut Minimum amount of eDai being bought
    function sellDai(address pool, address to, uint128 daiIn, uint128 minEDaiOut)
        external
        returns(uint256)
    {
        uint256 eDaiOut = IPool(pool).sellDai(msg.sender, to, daiIn);
        require(
            eDaiOut >= minEDaiOut,
            "YieldProxy: Limit not reached"
        );
        return eDaiOut;
    }

    /// @dev Buy Dai for eDai
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought
    /// @param maxEDaiIn Maximum amount of eDai being sold
    function buyDai(address pool, address to, uint128 daiOut, uint128 maxEDaiIn)
        public
        returns(uint256)
    {
        uint256 eDaiIn = IPool(pool).buyDai(msg.sender, to, daiOut);
        require(
            maxEDaiIn >= eDaiIn,
            "YieldProxy: Limit exceeded"
        );
        return eDaiIn;
    }

    /// @dev Buy Dai for eDai and permits infinite eDai to the pool
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought
    /// @param maxEDaiIn Maximum amount of eDai being sold
    /// @param signature The `permit` call's signature
    function buyDaiWithSignature(address pool, address to, uint128 daiOut, uint128 maxEDaiIn, bytes memory signature)
        external
        returns(uint256)
    {
        (bytes32 r, bytes32 s, uint8 v) = unpack(signature);
        IPool(pool).eDai().permit(msg.sender, address(pool), uint(-1), uint(-1), v, r, s);

        return buyDai(pool, to, daiOut, maxEDaiIn);
    }

    /// @dev Sell eDai for Dai
    /// @param to Wallet receiving the dai being bought
    /// @param eDaiIn Amount of eDai being sold
    /// @param minDaiOut Minimum amount of dai being bought
    function sellEDai(address pool, address to, uint128 eDaiIn, uint128 minDaiOut)
        external
        returns(uint256)
    {
        uint256 daiOut = IPool(pool).sellEDai(msg.sender, to, eDaiIn);
        require(
            daiOut >= minDaiOut,
            "YieldProxy: Limit not reached"
        );
        return daiOut;
    }

    /// @dev Buy eDai for dai
    /// @param to Wallet receiving the eDai being bought
    /// @param eDaiOut Amount of eDai being bought
    /// @param maxDaiIn Maximum amount of dai being sold
    function buyEDai(address pool, address to, uint128 eDaiOut, uint128 maxDaiIn)
        external
        returns(uint256)
    {
        uint256 daiIn = IPool(pool).buyEDai(msg.sender, to, eDaiOut);
        require(
            maxDaiIn >= daiIn,
            "YieldProxy: Limit exceeded"
        );
        return daiIn;
    }

    /// @dev Burns Dai from caller to repay debt in a Yield Vault.
    /// User debt is decreased for the given collateral and eDai series, in Yield vault `to`.
    /// The amount of debt repaid changes according to series maturity and MakerDAO rate and chi, depending on collateral type.
    /// `A signature is provided as a parameter to this function, so that `dai.approve()` doesn't need to be called.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield vault to repay debt for.
    /// @param daiAmount Amount of Dai to use for debt repayment.
    /// @param signature The `permit` call's signature
    function repayDaiWithSignature(bytes32 collateral, uint256 maturity, address to, uint256 daiAmount, bytes memory signature)
        external
        returns(uint256)
    {
        (bytes32 r, bytes32 s, uint8 v) = unpack(signature);
        dai.permit(msg.sender, address(treasury), dai.nonces(msg.sender), uint(-1), true, v, r, s);
        controller.repayDai(collateral, maturity, msg.sender, to, daiAmount);
    }


    // YieldProxy: Maker to Yield proxy

    /// @dev Transfer debt and collateral from MakerDAO to Yield
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore eDai series to borrow)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    function makerToYield(address pool, address user, uint256 wethAmount, uint256 daiAmount) public {
        // The user specifies the eDai he wants to mint to cover his maker debt, the weth to be passed on as collateral, and the dai debt to move
        (uint256 ink, uint256 art) = vat.urns(WETH, user);
        (, uint256 rate,,,) = vat.ilks("ETH-A");
        require(
            daiAmount <= muld(art, rate),
            "YieldProxy: Not enough debt in Maker"
        );
        require(
            wethAmount <= ink,
            "YieldProxy: Not enough collateral in Maker"
        );
        // Flash mint the eDai
        IEDai eDai = IPool(pool).eDai();
        eDai.flashMint(
            address(this),
            eDaiForDai(pool, daiAmount),
            abi.encode(MTY, pool, user, wethAmount, daiAmount)
        );
    }

    /// @dev Transfer debt and collateral from Yield to MakerDAO
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore eDai series to migrate)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    /// @param eDaiAmount eDai debt to move from Yield to MakerDAO.
    function yieldToMaker(address pool, address user, uint256 wethAmount, uint256 eDaiAmount) public {
        IEDai eDai = IPool(pool).eDai();

        // The user specifies the eDai he wants to move, and the weth to be passed on as collateral
        require(
            eDaiAmount <= controller.debtEDai(WETH, eDai.maturity(), user),
            "YieldProxy: Not enough debt in Yield"
        );
        require(
            wethAmount <= controller.posted(WETH, user),
            "YieldProxy: Not enough collateral in Yield"
        );
        // Flash mint the eDai
        eDai.flashMint(
            address(this),
            eDaiAmount,
            abi.encode(YTM, pool, user, wethAmount, 0)
        ); // The daiAmount encoded is ignored
    }

    /// @dev Callback from `EDai.flashMint()`
    function executeOnFlashMint(address, uint256 eDaiAmount, bytes calldata data) external override {
        (bool direction, address pool, address user, uint256 wethAmount, uint256 daiAmount) = 
            abi.decode(data, (bool, address, address, uint256, uint256));
        if(direction == MTY) _makerToYield(pool, user, wethAmount, daiAmount);
        if(direction == YTM) _yieldToMaker(pool, user, wethAmount, eDaiAmount);
    }

    /// @dev Minimum weth needed to collateralize an amount of dai in MakerDAO
    function wethForDai(uint256 daiAmount) public view returns (uint256) {
        (,, uint256 spot,,) = vat.ilks("ETH-A");
        return divd(daiAmount, spot);
    }

    /// @dev Minimum weth needed to collateralize an amount of eDai in Yield. Yes, it's the same formula.
    function wethForEDai(uint256 eDaiAmount) public view returns (uint256) {
        (,, uint256 spot,,) = vat.ilks("ETH-A");
        return divd(eDaiAmount, spot);
    }

    /// @dev Amount of eDai debt that will result from migrating Dai debt from MakerDAO to Yield
    function eDaiForDai(address pool, uint256 daiAmount) public view returns (uint256) {
        return IPool(pool).buyDaiPreview(daiAmount.toUint128());
    }

    /// @dev Amount of dai debt that will result from migrating eDai debt from Yield to MakerDAO
    function daiForEDai(address pool, uint256 eDaiAmount) public view returns (uint256) {
        return IPool(pool).buyEDaiPreview(eDaiAmount.toUint128());
    }

    /// @dev Internal function to transfer debt and collateral from MakerDAO to Yield
    /// @param pool The pool to trade in (and therefore eDai series to borrow)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    function _makerToYield(address pool, address user, uint256 wethAmount, uint256 daiAmount) internal {
        IPool _pool = IPool(pool);
        IEDai eDai = IEDai(_pool.eDai());

        // Pool should take exactly all eDai flash minted. YieldProxy will hold the dai temporarily
        uint256 eDaiSold = _pool.buyDai(address(this), address(this), daiAmount.toUint128());

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
        controller.borrow(WETH, eDai.maturity(), user, address(this), eDaiSold); // Borrow the eDai
    }


    /// @dev Internal function to transfer debt and collateral from Yield to MakerDAO
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore eDai series to migrate)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    /// @param eDaiAmount eDai debt to move from Yield to MakerDAO.
    function _yieldToMaker(address pool, address user, uint256 wethAmount, uint256 eDaiAmount) internal {
        IPool _pool = IPool(pool);
        IEDai eDai = IEDai(_pool.eDai());

        // Pay the Yield debt - YieldProxy pays EDai to remove the debt of `user`
        // Controller should take exactly all eDai flash minted.
        controller.repayEDai(WETH, eDai.maturity(), address(this), user, eDaiAmount);

        // Withdraw the collateral from Yield, YieldProxy will hold it
        controller.withdraw(WETH, user, address(this), wethAmount);

        // Post the collateral to Maker, in the `user` vault
        wethJoin.join(user, wethAmount);

        // We are going to need to buy the EDai back with Dai borrowed from Maker
        uint256 daiAmount = _pool.buyEDaiPreview(eDaiAmount.toUint128());

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

        // Sell the Dai for EDai at Pool - It should make up for what was taken with repayYdai
        _pool.buyEDai(address(this), address(this), eDaiAmount.toUint128());
    }
}
