// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../helpers/DecimalMath.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IGemJoin.sol";
import "../interfaces/IDaiJoin.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IChai.sol";
import "../interfaces/IYDai.sol";
import "../interfaces/IController.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IFlashMinter.sol";


/// @dev Splitter migrates vaults between MakerDAO and Yield using flash minting.
contract Splitter is IFlashMinter, DecimalMath {

    bytes32 public constant WETH = "ETH-A";
    bool constant public MTY = true;
    bool constant public YTM = false;

    IVat public vat;
    IERC20 public weth;
    IERC20 public dai;
    IGemJoin public wethJoin;
    IDaiJoin public daiJoin;
    IYDai public yDai;
    IController public controller;
    IPool public pool;

    constructor(
        address vat_,
        address weth_,
        address dai_,
        address wethJoin_,
        address daiJoin_,
        address treasury_,
        address yDai_,
        address controller_,
        address pool_
    ) public {
        vat = IVat(vat_);
        weth = IERC20(weth_);
        dai = IERC20(dai_);
        wethJoin = IGemJoin(wethJoin_);
        daiJoin = IDaiJoin(daiJoin_);
        yDai = IYDai(yDai_);
        controller = IController(controller_);
        pool = IPool(pool_);

        vat.hope(daiJoin_);
        vat.hope(wethJoin_);

        dai.approve(pool_, uint256(-1));
        yDai.approve(pool_, uint256(-1));
        dai.approve(daiJoin_, uint(-1));
        weth.approve(wethJoin_, uint(-1));
        weth.approve(treasury_, uint(-1));
    }

    /// @dev Safe casting from uint256 to int256
    function toInt256(uint256 x) internal pure returns(int256) {
        require(
            x <= 57896044618658097711785492504343953926634992332820282019728792003956564819967,
            "Treasury: Cast overflow"
        );
        return int256(x);
    }
    
    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= 340282366920938463463374607431768211455,
            "Pool: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Transfer debt and collateral from MakerDAO to Yield
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    function makerToYield(address user, uint256 wethAmount, uint256 daiAmount) public {
        // The user specifies the yDai he wants to mint to cover his maker debt, the weth to be passed on as collateral, and the dai debt to move
        (uint256 ink, uint256 art) = vat.urns(WETH, user);
        (, uint256 rate,,,) = vat.ilks("ETH-A");
        require(
            daiAmount <= muld(art, rate),
            "Splitter: Not enough debt in Maker"
        );
        require(
            wethAmount <= ink,
            "Splitter: Not enough collateral in Maker"
        );
        // Flash mint the yDai
        yDai.flashMint(
            address(this),
            yDaiForDai(daiAmount),
            abi.encode(MTY, user, wethAmount, daiAmount)
        );
    }

    /// @dev Transfer debt and collateral from Yield to MakerDAO
    /// @param user Vault to migrate.
    /// @param yDaiAmount yDai debt to move from Yield to MakerDAO.
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    function yieldToMaker(address user, uint256 yDaiAmount, uint256 wethAmount) public {
        // The user specifies the yDai he wants to move, and the weth to be passed on as collateral
        require(
            yDaiAmount <= controller.debtYDai(WETH, yDai.maturity(), user),
            "Splitter: Not enough debt in Yield"
        );
        require(
            wethAmount <= controller.posted(WETH, user),
            "Splitter: Not enough collateral in Yield"
        );
        // Flash mint the yDai
        yDai.flashMint(
            address(this),
            yDaiAmount,
            abi.encode(YTM, user, wethAmount, 0)
        ); // The daiAmount encoded is ignored
    }

    /// @dev Callback from `YDai.flashMint()`
    function executeOnFlashMint(address, uint256 yDaiAmount, bytes calldata data) external override {
        (bool direction, address user, uint256 wethAmount, uint256 daiAmount) = abi.decode(data, (bool, address, uint256, uint256));
        if(direction == MTY) _makerToYield(user, wethAmount, daiAmount);
        if(direction == YTM) _yieldToMaker(user, yDaiAmount, wethAmount);
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
    function yDaiForDai(uint256 daiAmount) public view returns (uint256) {
        return pool.buyDaiPreview(toUint128(daiAmount));
    }

    /// @dev Amount of dai debt that will result from migrating yDai debt from Yield to MakerDAO
    function daiForYDai(uint256 yDaiAmount) public view returns (uint256) {
        return pool.buyYDaiPreview(toUint128(yDaiAmount));
    }

    /// @dev Internal function to transfer debt and collateral from MakerDAO to Yield
    /// @param user Vault to migrate.
    /// @param wethAmount weth to move from MakerDAO to Yield. Needs to be high enough to collateralize the dai debt in Yield,
    /// and low enough to make sure that debt left in MakerDAO is also collateralized.
    /// @param daiAmount dai debt to move from MakerDAO to Yield. Denominated in Dai (= art * rate)
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    function _makerToYield(address user, uint256 wethAmount, uint256 daiAmount) internal {

        // Pool should take exactly all yDai flash minted. Splitter will hold the dai temporarily
        uint256 yDaiSold = pool.buyDai(address(this), address(this), toUint128(daiAmount));

        daiJoin.join(user, daiAmount);      // Put the Dai in Maker
        (, uint256 rate,,,) = vat.ilks("ETH-A");
        vat.frob(                           // Pay the debt and unlock collateral in Maker
            "ETH-A",
            user,
            user,
            user,
            -toInt256(wethAmount),               // Removing Weth collateral
            -toInt256(divdrup(daiAmount, rate))  // Removing Dai debt
        );

        vat.flux("ETH-A", user, address(this), wethAmount);             // Remove the collateral from Maker
        wethJoin.exit(address(this), wethAmount);                       // Hold the weth in Splitter
        controller.post(WETH, address(this), user, wethAmount);         // Add the collateral to Yield
        controller.borrow(WETH, yDai.maturity(), user, address(this), yDaiSold); // Borrow the yDai
    }


    /// @dev Internal function to transfer debt and collateral from Yield to MakerDAO
    /// @param user Vault to migrate.
    /// @param yDaiAmount yDai debt to move from Yield to MakerDAO.
    /// @param wethAmount weth to move from Yield to MakerDAO. Needs to be high enough to collateralize the dai debt in MakerDAO,
    /// and low enough to make sure that debt left in Yield is also collateralized.
    /// Needs vat.hope(splitter.address, { from: user });
    /// Needs controller.addDelegate(splitter.address, { from: user });
    function _yieldToMaker(address user, uint256 yDaiAmount, uint256 wethAmount) internal {
        // Pay the Yield debt - Splitter pays YDai to remove the debt of `user`
        // Controller should take exactly all yDai flash minted.
        controller.repayYDai(WETH, yDai.maturity(), address(this), user, yDaiAmount);

        // Withdraw the collateral from Yield, Splitter will hold it
        controller.withdraw(WETH, user, address(this), wethAmount);

        // Post the collateral to Maker, in the `user` vault
        wethJoin.join(user, wethAmount);

        // We are going to need to buy the YDai back with Dai borrowed from Maker
        uint256 daiAmount = pool.buyYDaiPreview(toUint128(yDaiAmount));

        // Borrow the Dai from Maker
        (, uint256 rate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee for Weth
        vat.frob(
            "ETH-A",
            user,
            user,
            user,
            toInt256(wethAmount),                   // Adding Weth collateral
            toInt256(divdrup(daiAmount, rate))      // Adding Dai debt
        );
        vat.move(user, address(this), daiAmount.mul(UNIT)); // Transfer the Dai to Splitter within MakerDAO, in RAD
        daiJoin.exit(address(this), daiAmount);             // Splitter will hold the dai temporarily

        // Sell the Dai for YDai at Pool - It should make up for what was taken with repayYdai
        pool.buyYDai(address(this), address(this), toUint128(yDaiAmount));
    }
}