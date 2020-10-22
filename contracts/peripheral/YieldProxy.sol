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
import "../helpers/DecimalMath.sol";


interface ControllerLike is IDelegable {
    function treasury() external view returns (ITreasury);
    function series(uint256) external view returns (IFYDai);
    function seriesIterator(uint256) external view returns (uint256);
    function totalSeries() external view returns (uint256);
    function containsSeries(uint256) external view returns (bool);
    function posted(bytes32, address) external view returns (uint256);
    function locked(bytes32, address) external view returns (uint256);
    function debtFYDai(bytes32, uint256, address) external view returns (uint256);
    function debtDai(bytes32, uint256, address) external view returns (uint256);
    function totalDebtDai(bytes32, address) external view returns (uint256);
    function isCollateralized(bytes32, address) external view returns (bool);
    function inDai(bytes32, uint256, uint256) external view returns (uint256);
    function inFYDai(bytes32, uint256, uint256) external view returns (uint256);
    function erase(bytes32, address) external returns (uint256, uint256);
    function shutdown() external;
    function post(bytes32, address, address, uint256) external;
    function withdraw(bytes32, address, address, uint256) external;
    function borrow(bytes32, uint256, address, address, uint256) external;
    function repayFYDai(bytes32, uint256, address, address, uint256) external returns (uint256);
    function repayDai(bytes32, uint256, address, address, uint256) external returns (uint256);
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

    /// @dev Safe casting from uint256 to int256
    function toInt256(uint256 x) internal pure returns(int256) {
        require(
            x <= uint256(type(int256).max),
            "YieldProxy: Cast overflow"
        );
        return int256(x);
    }
}

contract YieldProxy is DecimalMath {
    using SafeCast for uint256;

    IVat public vat;
    IWeth public weth;
    IDai public dai;
    IGemJoin public wethJoin;
    IDaiJoin public daiJoin;
    IChai public chai;
    ControllerLike public controller;
    ITreasury public treasury;

    IPool[] public pools;
    mapping (address => bool) public poolsMap;

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";
    bool constant public MTY = true;
    bool constant public YTM = false;


    constructor(address controller_, IPool[] memory _pools) public {
        controller = ControllerLike(controller_);
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

    /// @dev Given a pool and 3 signatures, it `permit`'s dai and fyDai for that pool and adds it as a delegate
    function authorizePool(IPool pool, address from, bytes memory daiSig, bytes memory fyDaiSig, bytes memory poolSig) public {
        onlyKnownPool(pool);
        bytes32 r;
        bytes32 s;
        uint8 v;

        (r, s, v) = unpack(daiSig);
        dai.permit(from, address(pool), dai.nonces(from), uint(-1), true, v, r, s);

        (r, s, v) = unpack(fyDaiSig);
        pool.fyDai().permit(from, address(this), uint(-1), uint(-1), v, r, s);

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

    /// @dev Mints liquidity with provided Dai by borrowing fyDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxFYDai maximum amount of fyDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(IPool pool, uint256 daiUsed, uint256 maxFYDai) external returns (uint256) {
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
    function removeLiquidityEarlyDaiPool(IPool pool, uint256 poolTokens, uint256 minimumDaiPrice, uint256 minimumFYDaiPrice) external {
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
    function removeLiquidityEarlyDaiFixed(IPool pool, uint256 poolTokens, uint256 minimumFYDaiPrice) external {
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
    function removeLiquidityMature(IPool pool, uint256 poolTokens) external {
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
        onlyKnownPool(pool);
        uint256 fyDaiToBorrow = pool.buyDaiPreview(daiToBorrow.toUint128());
        require (fyDaiToBorrow <= maximumFYDai, "YieldProxy: Too much fyDai required");

        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), fyDaiToBorrow);
        pool.buyDai(address(this), to, daiToBorrow.toUint128());

        return fyDaiToBorrow;
    }

    /// @dev Borrow fyDai from Controller and sell it immediately for Dai, if a minimum amount of Dai can be obtained such.
    /// Must have approved the operator with `controller.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to sent the resulting Dai to.
    /// @param fyDaiToBorrow Amount of fyDai to borrow.
    /// @param minimumDaiToBorrow Minimum amount of Dai that should be borrowed.
    function borrowMinimumDaiForFYDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 fyDaiToBorrow,
        uint256 minimumDaiToBorrow
    )
        public
        returns (uint256)
    {
        onlyKnownPool(pool);
        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), fyDaiToBorrow);
        uint256 boughtDai = pool.sellFYDai(address(this), to, fyDaiToBorrow.toUint128());
        require (boughtDai >= minimumDaiToBorrow, "YieldProxy: Not enough Dai obtained");

        return boughtDai;
    }

    /// @dev Repay an amount of fyDai debt in Controller using Dai exchanged for fyDai at pool rates, up to a maximum amount of Dai spent.
    /// Must have approved the operator with `pool.addDelegate(yieldProxy.address)`.
    /// If `fyDaiRepayment` exceeds the existing debt, only the necessary fyDai will be used.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay fyDai debt for.
    /// @param fyDaiRepayment Amount of fyDai debt to repay.
    /// @param maximumRepaymentInDai Maximum amount of Dai that should be spent on the repayment.
    function repayFYDaiDebtForMaximumDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 fyDaiRepayment,
        uint256 maximumRepaymentInDai
    )
        public
        returns (uint256)
    {
        onlyKnownPool(pool);
        uint256 fyDaiDebt = controller.debtFYDai(collateral, maturity, to);
        uint256 fyDaiToUse = fyDaiDebt < fyDaiRepayment ? fyDaiDebt : fyDaiRepayment; // Use no more fyDai than debt
        uint256 repaymentInDai = pool.buyFYDai(msg.sender, address(this), fyDaiToUse.toUint128());
        require (repaymentInDai <= maximumRepaymentInDai, "YieldProxy: Too much Dai required");
        controller.repayFYDai(collateral, maturity, address(this), to, fyDaiToUse);

        return repaymentInDai;
    }

    /// @dev Repay an amount of fyDai debt in Controller using a given amount of Dai exchanged for fyDai at pool rates, with a minimum of fyDai debt required to be paid.
    /// Must have approved the operator with `pool.addDelegate(yieldProxy.address)`.
    /// If `repaymentInDai` exceeds the existing debt, only the necessary Dai will be used.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay fyDai debt for.
    /// @param minimumFYDaiRepayment Minimum amount of fyDai debt to repay.
    /// @param repaymentInDai Exact amount of Dai that should be spent on the repayment.
    function repayMinimumFYDaiDebtForDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 minimumFYDaiRepayment,
        uint256 repaymentInDai
    )
        public
        returns (uint256)
    {
        onlyKnownPool(pool);
        uint256 fyDaiRepayment = pool.sellDaiPreview(repaymentInDai.toUint128());
        uint256 fyDaiDebt = controller.debtFYDai(collateral, maturity, to);
        if(fyDaiRepayment <= fyDaiDebt) { // Sell no more Dai than needed to cancel all the debt
            pool.sellDai(msg.sender, address(this), repaymentInDai.toUint128());
        } else { // If we have too much Dai, then don't sell it all and buy the exact amount of fyDai needed instead.
            pool.buyFYDai(msg.sender, address(this), fyDaiDebt.toUint128());
            fyDaiRepayment = fyDaiDebt;
        }
        require (fyDaiRepayment >= minimumFYDaiRepayment, "YieldProxy: Not enough fyDai debt repaid");
        controller.repayFYDai(collateral, maturity, address(this), to, fyDaiRepayment);

        return fyDaiRepayment;
    }

    /// @dev Sell Dai for fyDai
    /// @param to Wallet receiving the fyDai being bought
    /// @param daiIn Amount of dai being sold
    /// @param minFYDaiOut Minimum amount of fyDai being bought
    function sellDai(IPool pool, address to, uint128 daiIn, uint128 minFYDaiOut)
        external
        returns(uint256)
    {
        onlyKnownPool(pool);
        uint256 fyDaiOut = pool.sellDai(msg.sender, to, daiIn);
        require(
            fyDaiOut >= minFYDaiOut,
            "YieldProxy: Limit not reached"
        );
        return fyDaiOut;
    }

    /// @dev Buy Dai for fyDai
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought
    /// @param maxFYDaiIn Maximum amount of fyDai being sold
    function buyDai(IPool pool, address to, uint128 daiOut, uint128 maxFYDaiIn)
        public
        returns(uint256)
    {
        onlyKnownPool(pool);
        uint256 fyDaiIn = pool.buyDai(msg.sender, to, daiOut);
        require(
            maxFYDaiIn >= fyDaiIn,
            "YieldProxy: Limit exceeded"
        );
        return fyDaiIn;
    }

    /// @dev Buy Dai for fyDai and permits infinite fyDai to the pool
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought
    /// @param maxFYDaiIn Maximum amount of fyDai being sold
    /// @param signature The `permit` call's signature
    function buyDaiWithSignature(IPool pool, address to, uint128 daiOut, uint128 maxFYDaiIn, bytes memory signature)
        external
        returns(uint256)
    {
        onlyKnownPool(pool);
        (bytes32 r, bytes32 s, uint8 v) = unpack(signature);
        pool.fyDai().permit(msg.sender, address(pool), uint(-1), uint(-1), v, r, s);

        return buyDai(pool, to, daiOut, maxFYDaiIn);
    }

    /// @dev Sell fyDai for Dai
    /// @param to Wallet receiving the dai being bought
    /// @param fyDaiIn Amount of fyDai being sold
    /// @param minDaiOut Minimum amount of dai being bought
    function sellFYDai(IPool pool, address to, uint128 fyDaiIn, uint128 minDaiOut)
        public
        returns(uint256)
    {
        onlyKnownPool(pool);
        uint256 daiOut = pool.sellFYDai(msg.sender, to, fyDaiIn);
        require(
            daiOut >= minDaiOut,
            "YieldProxy: Limit not reached"
        );
        return daiOut;
    }

    /// @dev Sell fyDai for Dai and permits infinite Dai to the pool
    /// @param to Wallet receiving the dai being bought
    /// @param fyDaiIn Amount of fyDai being sold
    /// @param minDaiOut Minimum amount of dai being bought
    /// @param signature The `permit` call's signature
    function sellFYDaiWithSignature(IPool pool, address to, uint128 fyDaiIn, uint128 minDaiOut, bytes memory signature)
        external
        returns(uint256)
    {
        onlyKnownPool(pool);
        (bytes32 r, bytes32 s, uint8 v) = unpack(signature);
        pool.fyDai().permit(msg.sender, address(pool), uint(-1), uint(-1), v, r, s);

        return sellFYDai(pool, to, fyDaiIn, minDaiOut);
    }

    /// @dev Buy fyDai for dai
    /// @param to Wallet receiving the fyDai being bought
    /// @param fyDaiOut Amount of fyDai being bought
    /// @param maxDaiIn Maximum amount of dai being sold
    function buyFYDai(IPool pool, address to, uint128 fyDaiOut, uint128 maxDaiIn)
        external
        returns(uint256)
    {
        onlyKnownPool(pool);
        uint256 daiIn = pool.buyFYDai(msg.sender, to, fyDaiOut);
        require(
            maxDaiIn >= daiIn,
            "YieldProxy: Limit exceeded"
        );
        return daiIn;
    }

    /// @dev Burns Dai from caller to repay debt in a Yield Vault.
    /// User debt is decreased for the given collateral and fyDai series, in Yield vault `to`.
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

    function onlyKnownPool(IPool pool) private view {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
    }
}
