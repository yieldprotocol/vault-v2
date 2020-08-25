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
import "../interfaces/IYDai.sol";
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

    IController public controller;

    IVat public vat;
    IDai public dai;
    IChai public chai;
    IWeth public weth;
    IGemJoin public wethJoin;
    IDaiJoin public daiJoin;

    IPool[] public pools;
    mapping (address => bool) public poolsMap;

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";
    bool constant public MTY = true;
    bool constant public YTM = false;


    constructor(address controller_, IPool[] memory _pools) public {
        controller = IController(controller_);
        ITreasury treasury = controller.treasury();

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

        // allow all the pools to pull YDai/dai from us for LPing
        for (uint i = 0 ; i < _pools.length; i++) {
            dai.approve(address(_pools[i]), uint(-1));
            _pools[i].yDai().approve(address(_pools[i]), uint(-1));
            poolsMap[address(_pools[i])]= true;
        }

        pools = _pools;
    }

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

    /// @dev Given a pool and 3 signatures, it `permit`'s dai and yDAI for that pool and adds it as a delegate
    function authorizePool(IPool pool, address from, bytes memory daiSig, bytes memory yDaiSig, bytes memory poolSig) public {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        bytes32 r;
        bytes32 s;
        uint8 v;

        (r, s, v) = unpack(daiSig);
        dai.permit(from, address(pool), dai.nonces(from), uint(-1), true, v, r, s);

        (r, s, v) = unpack(yDaiSig);
        pool.yDai().permit(from, address(this), uint(-1), uint(-1), v, r, s);

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

    /// @dev Mints liquidity with provided Dai by borrowing yDai with some of the Dai.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the dai transfer with `dai.approve(daiUsed)`
    /// @param daiUsed amount of Dai to use to mint liquidity. 
    /// @param maxYDai maximum amount of yDai to be borrowed to mint liquidity. 
    /// @return The amount of liquidity tokens minted.  
    function addLiquidity(IPool pool, uint256 daiUsed, uint256 maxYDai) external returns (uint256) {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        IYDai yDai = pool.yDai();
        require(yDai.isMature() != true, "YieldProxy: Only before maturity");
        require(dai.transferFrom(msg.sender, address(this), daiUsed), "YieldProxy: Transfer Failed");

        // calculate needed yDai
        uint256 daiReserves = dai.balanceOf(address(pool));
        uint256 yDaiReserves = yDai.balanceOf(address(pool));
        uint256 daiToAdd = daiUsed.mul(daiReserves).div(yDaiReserves.add(daiReserves));
        uint256 daiToConvert = daiUsed.sub(daiToAdd);
        require(
            daiToConvert <= maxYDai,
            "YieldProxy: maxYDai exceeded"
        ); // 1 Dai == 1 yDai

        // convert dai to chai and borrow needed yDai
        chai.join(address(this), daiToConvert);
        // look at the balance of chai in dai to avoid rounding issues
        uint256 toBorrow = chai.dai(address(this));
        controller.post(CHAI, address(this), msg.sender, chai.balanceOf(address(this)));
        controller.borrow(CHAI, yDai.maturity(), msg.sender, address(this), toBorrow);
        
        // mint liquidity tokens
        return pool.mint(address(this), msg.sender, daiToAdd);
    }

    /// @dev Burns tokens and repays yDai debt. Buys needed yDai or sells any excess, and all Dai is returned.
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)` and `pool.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn. 
    /// @param minimumDai minimum amount of Dai to be bought with yDai when burning. 
    function removeLiquidityEarly(IPool pool, uint256 poolTokens, uint256 minimumDai) external {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        IYDai yDai = pool.yDai();
        (uint256 daiObtained, uint256 yDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);
        repayDebt(yDai, daiObtained, yDaiObtained);
        uint256 remainingYDai = yDai.balanceOf(address(this));
        if (remainingYDai > 0) {
            require(
                pool.sellYDai(address(this), address(this), uint128(remainingYDai)) >= minimumDai,
                "YieldProxy: minimumDai not reached"
            );
        }
        withdrawAssets(yDai);
    }

    /// @dev Burns tokens and repays yDai debt after Maturity. 
    /// Caller must have approved the proxy using`controller.addDelegate(yieldProxy)`
    /// Caller must have approved the liquidity burn with `pool.approve(poolTokens)`
    /// @param poolTokens amount of pool tokens to burn.
    function removeLiquidityMature(IPool pool, uint256 poolTokens) external {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        IYDai yDai = pool.yDai();
        (uint256 daiObtained, uint256 yDaiObtained) = pool.burn(msg.sender, address(this), poolTokens);
        if (yDaiObtained > 0) yDai.redeem(address(this), address(this), yDaiObtained);
        repayDebt(yDai, daiObtained, 0);
        withdrawAssets(yDai);
    }

    /// @dev Repay debt from the caller using the dai and yDai supplied
    /// @param daiAvailable amount of dai to use for repayments.
    /// @param yDaiAvailable amount of yDai to use for repayments.
    function repayDebt(IYDai yDai, uint256 daiAvailable, uint256 yDaiAvailable) internal {
        uint256 maturity = yDai.maturity();
        if (yDaiAvailable > 0 && controller.debtYDai(CHAI, maturity, msg.sender) > 0) {
            controller.repayYDai(CHAI, maturity, address(this), msg.sender, yDaiAvailable);
        }
        if (daiAvailable > 0 && controller.debtYDai(CHAI, maturity, msg.sender) > 0) {
            controller.repayDai(CHAI, maturity, address(this), msg.sender, daiAvailable);
        }
    }

    /// @dev Return to caller all posted chai if there is no debt, converted to dai, plus any dai remaining in the contract.
    function withdrawAssets(IYDai yDai) internal {
        if (controller.debtYDai(CHAI, yDai.maturity(), msg.sender) == 0) {
            controller.withdraw(CHAI, msg.sender, address(this), controller.posted(CHAI, msg.sender));
            chai.exit(address(this), chai.balanceOf(address(this)));
        }
        require(dai.transfer(msg.sender, dai.balanceOf(address(this))), "YieldProxy: Dai Transfer Failed");
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, for a maximum yDai debt.
    /// Must have approved the operator with `controller.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to send the resulting Dai to.
    /// @param maximumYDai Maximum amount of YDai to borrow.
    /// @param daiToBorrow Exact amount of Dai that should be obtained.
    function borrowDaiForMaximumYDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 maximumYDai,
        uint256 daiToBorrow
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        uint256 yDaiToBorrow = pool.buyDaiPreview(daiToBorrow.toUint128());
        require (yDaiToBorrow <= maximumYDai, "YieldProxy: Too much yDai required");

        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), yDaiToBorrow);
        pool.buyDai(address(this), to, daiToBorrow.toUint128());

        return yDaiToBorrow;
    }

    /// @dev Borrow yDai from Controller and sell it immediately for Dai, if a minimum amount of Dai can be obtained such.
    /// Must have approved the operator with `controller.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Wallet to sent the resulting Dai to.
    /// @param yDaiToBorrow Amount of yDai to borrow.
    /// @param minimumDaiToBorrow Minimum amount of Dai that should be borrowed.
    function borrowMinimumDaiForYDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 yDaiToBorrow,
        uint256 minimumDaiToBorrow
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        // The collateral for this borrow needs to have been posted beforehand
        controller.borrow(collateral, maturity, msg.sender, address(this), yDaiToBorrow);
        uint256 boughtDai = pool.sellYDai(address(this), to, yDaiToBorrow.toUint128());
        require (boughtDai >= minimumDaiToBorrow, "YieldProxy: Not enough Dai obtained");

        return boughtDai;
    }


    /// @dev Repay an amount of yDai debt in Controller using Dai exchanged for yDai at pool rates, up to a maximum amount of Dai spent.
    /// Must have approved the operator with `pool.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param yDaiRepayment Amount of yDai debt to repay.
    /// @param maximumRepaymentInDai Maximum amount of Dai that should be spent on the repayment.
    function repayYDaiDebtForMaximumDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 yDaiRepayment,
        uint256 maximumRepaymentInDai
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        uint256 repaymentInDai = pool.buyYDai(msg.sender, address(this), yDaiRepayment.toUint128());
        require (repaymentInDai <= maximumRepaymentInDai, "YieldProxy: Too much Dai required");
        controller.repayYDai(collateral, maturity, address(this), to, yDaiRepayment);

        return repaymentInDai;
    }

    /// @dev Repay an amount of yDai debt in Controller using a given amount of Dai exchanged for yDai at pool rates, with a minimum of yDai debt required to be paid.
    /// Must have approved the operator with `pool.addDelegate(yieldProxy.address)`.
    /// @param collateral Valid collateral type.
    /// @param maturity Maturity of an added series
    /// @param to Yield Vault to repay yDai debt for.
    /// @param minimumYDaiRepayment Minimum amount of yDai debt to repay.
    /// @param repaymentInDai Exact amount of Dai that should be spent on the repayment.
    function repayMinimumYDaiDebtForDai(
        IPool pool,
        bytes32 collateral,
        uint256 maturity,
        address to,
        uint256 minimumYDaiRepayment,
        uint256 repaymentInDai
    )
        public
        returns (uint256)
    {
        require(poolsMap[address(pool)], "YieldProxy: Unknown pool");
        uint256 yDaiRepayment = pool.sellDai(msg.sender, address(this), repaymentInDai.toUint128());
        require (yDaiRepayment >= minimumYDaiRepayment, "YieldProxy: Not enough yDai debt repaid");
        controller.repayYDai(collateral, maturity, address(this), to, yDaiRepayment);

        return yDaiRepayment;
    }

    /// @dev Sell Dai for yDai
    /// @param to Wallet receiving the yDai being bought
    /// @param daiIn Amount of dai being sold
    /// @param minYDaiOut Minimum amount of yDai being bought
    function sellDai(address pool, address to, uint128 daiIn, uint128 minYDaiOut)
        external
        returns(uint256)
    {
        uint256 yDaiOut = IPool(pool).sellDai(msg.sender, to, daiIn);
        require(
            yDaiOut >= minYDaiOut,
            "YieldProxy: Limit not reached"
        );
        return yDaiOut;
    }

    /// @dev Buy Dai for yDai
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought
    /// @param maxYDaiIn Maximum amount of yDai being sold
    function buyDai(address pool, address to, uint128 daiOut, uint128 maxYDaiIn)
        external
        returns(uint256)
    {
        uint256 yDaiIn = IPool(pool).buyDai(msg.sender, to, daiOut);
        require(
            maxYDaiIn >= yDaiIn,
            "YieldProxy: Limit exceeded"
        );
        return yDaiIn;
    }

    /// @dev Sell yDai for Dai
    /// @param to Wallet receiving the dai being bought
    /// @param yDaiIn Amount of yDai being sold
    /// @param minDaiOut Minimum amount of dai being bought
    function sellYDai(address pool, address to, uint128 yDaiIn, uint128 minDaiOut)
        external
        returns(uint256)
    {
        uint256 daiOut = IPool(pool).sellYDai(msg.sender, to, yDaiIn);
        require(
            daiOut >= minDaiOut,
            "YieldProxy: Limit not reached"
        );
        return daiOut;
    }

    /// @dev Buy yDai for dai
    /// @param to Wallet receiving the yDai being bought
    /// @param yDaiOut Amount of yDai being bought
    /// @param maxDaiIn Maximum amount of dai being sold
    function buyYDai(address pool, address to, uint128 yDaiOut, uint128 maxDaiIn)
        external
        returns(uint256)
    {
        uint256 daiIn = IPool(pool).buyYDai(msg.sender, to, yDaiOut);
        require(
            maxDaiIn >= daiIn,
            "YieldProxy: Limit exceeded"
        );
        return daiIn;
    }

    // YieldProxy: Maker to Yield proxy

    /// @dev Transfer debt and collateral from MakerDAO to Yield
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore yDai series to borrow)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    function makerToYield(address pool, address user, uint256 wethAmount, uint256 daiAmount) public {
        // The user specifies the yDai he wants to mint to cover his maker debt, the weth to be passed on as collateral, and the dai debt to move
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
        // Flash mint the yDai
        IYDai yDai = IPool(pool).yDai();
        yDai.flashMint(
            address(this),
            yDaiForDai(pool, daiAmount),
            abi.encode(MTY, pool, user, wethAmount, daiAmount)
        );
    }

    /// @dev Transfer debt and collateral from Yield to MakerDAO
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore yDai series to migrate)
    /// @param user Vault to migrate.
    /// @param yDaiAmount yDai debt to move from Yield to MakerDAO.
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    function yieldToMaker(address pool, address user, uint256 yDaiAmount, uint256 wethAmount) public {
        IYDai yDai = IPool(pool).yDai();

        // The user specifies the yDai he wants to move, and the weth to be passed on as collateral
        require(
            yDaiAmount <= controller.debtYDai(WETH, yDai.maturity(), user),
            "YieldProxy: Not enough debt in Yield"
        );
        require(
            wethAmount <= controller.posted(WETH, user),
            "YieldProxy: Not enough collateral in Yield"
        );
        // Flash mint the yDai
        yDai.flashMint(
            address(this),
            yDaiAmount,
            abi.encode(YTM, pool, user, wethAmount, 0)
        ); // The daiAmount encoded is ignored
    }

    /// @dev Callback from `YDai.flashMint()`
    function executeOnFlashMint(address, uint256 yDaiAmount, bytes calldata data) external override {
        (bool direction, address pool, address user, uint256 wethAmount, uint256 daiAmount) = 
            abi.decode(data, (bool, address, address, uint256, uint256));
        if(direction == MTY) _makerToYield(pool, user, wethAmount, daiAmount);
        if(direction == YTM) _yieldToMaker(pool, user, yDaiAmount, wethAmount);
    }

    /// @dev Minimum weth needed to collateralize an amount of dai in MakerDAO
    function wethForDai(uint256 daiAmount) public view returns (uint256) {
        (,, uint256 spot,,) = vat.ilks("ETH-A");
        return divd(daiAmount, spot);
    }

    /// @dev Minimum weth needed to collateralize an amount of yDai in Yield. Yes, it's the same formula.
    function wethForYDai(uint256 yDaiAmount) public view returns (uint256) {
        (,, uint256 spot,,) = vat.ilks("ETH-A");
        return divd(yDaiAmount, spot);
    }

    /// @dev Amount of yDai debt that will result from migrating Dai debt from MakerDAO to Yield
    function yDaiForDai(address pool, uint256 daiAmount) public view returns (uint256) {
        return IPool(pool).buyDaiPreview(daiAmount.toUint128());
    }

    /// @dev Amount of dai debt that will result from migrating yDai debt from Yield to MakerDAO
    function daiForYDai(address pool, uint256 yDaiAmount) public view returns (uint256) {
        return IPool(pool).buyYDaiPreview(yDaiAmount.toUint128());
    }

    /// @dev Internal function to transfer debt and collateral from MakerDAO to Yield
    /// @param pool The pool to trade in (and therefore yDai series to borrow)
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    function _makerToYield(address pool, address user, uint256 wethAmount, uint256 daiAmount) internal {
        IPool _pool = IPool(pool);
        IYDai yDai = IYDai(_pool.yDai());

        // Pool should take exactly all yDai flash minted. YieldProxy will hold the dai temporarily
        uint256 yDaiSold = _pool.buyDai(address(this), address(this), daiAmount.toUint128());

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
        controller.borrow(WETH, yDai.maturity(), user, address(this), yDaiSold); // Borrow the yDai
    }


    /// @dev Internal function to transfer debt and collateral from Yield to MakerDAO
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    /// @param pool The pool to trade in (and therefore yDai series to migrate)
    /// @param user Vault to migrate.
    /// @param yDaiAmount yDai debt to move from Yield to MakerDAO.
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    function _yieldToMaker(address pool, address user, uint256 yDaiAmount, uint256 wethAmount) internal {
        IPool _pool = IPool(pool);
        IYDai yDai = IYDai(_pool.yDai());

        // Pay the Yield debt - YieldProxy pays YDai to remove the debt of `user`
        // Controller should take exactly all yDai flash minted.
        controller.repayYDai(WETH, yDai.maturity(), address(this), user, yDaiAmount);

        // Withdraw the collateral from Yield, YieldProxy will hold it
        controller.withdraw(WETH, user, address(this), wethAmount);

        // Post the collateral to Maker, in the `user` vault
        wethJoin.join(user, wethAmount);

        // We are going to need to buy the YDai back with Dai borrowed from Maker
        uint256 daiAmount = _pool.buyYDaiPreview(yDaiAmount.toUint128());

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

        // Sell the Dai for YDai at Pool - It should make up for what was taken with repayYdai
        _pool.buyYDai(address(this), address(this), yDaiAmount.toUint128());
    }
}
