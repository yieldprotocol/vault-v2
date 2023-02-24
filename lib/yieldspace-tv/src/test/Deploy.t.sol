// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import "../Pool/PoolErrors.sol";
import {Pool} from "../Pool/Pool.sol";
import {Math64x64} from "../Math64x64.sol";
import {TestCore} from "./shared/TestCore.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {FYTokenMock} from "./mocks/FYTokenMock.sol";
import {IERC20Like} from "../interfaces/IERC20Like.sol";
import {ERC4626TokenMock} from "./mocks/ERC4626TokenMock.sol";

contract Deploy is TestCore {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    ERC20Mock public assetDAI;
    ERC20Mock public assetUSDC;
    ERC20Mock public asset20DECI;
    IERC20Like public shares4626DAI;
    IERC20Like public shares4626USDC;
    IERC20Like public shares462620DECI;
    FYTokenMock public fyDAI;
    FYTokenMock public fyUSDC;
    FYTokenMock public fy20DECI;

    function setUp() public virtual {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        assetDAI = new ERC20Mock("DAI", "DAI", 18);
        assetUSDC = new ERC20Mock("USDC", "USDC", 6);
        asset20DECI = new ERC20Mock("20DECI", "20DECI", 20);

        shares4626DAI = IERC20Like(address(new ERC4626TokenMock("4626DAI", "4626DAI", 18, address(assetDAI))));

        shares4626USDC = IERC20Like(address(new ERC4626TokenMock("4626USDC", "4626USDC", 6, address(assetUSDC))));

        shares462620DECI = IERC20Like(
            address(new ERC4626TokenMock("462620DECI", "462620DECI", 20, address(asset20DECI)))
        );

        // TODO: Add tests for Euler, Non-TV, maybe not Yearn if we're not using it
        // sharesYV = IERC20Like(address(new YVTokenMock(sharesName, sharesSymbol, assetDecimals, address(asset))));
        // sharesEuler = IERC20Like(address(new ETokenMock(sharesName, sharesSymbol, 18, address(euler), address(asset))));

        // Create fyTokens
        fyDAI = new FYTokenMock("fyDAI", "fyDAI", address(assetDAI), maturity);
        fyUSDC = new FYTokenMock("fyUSDC", "fyUSDC", address(assetUSDC), maturity);
        fy20DECI = new FYTokenMock("fy20DECI", "fy20DECI", address(asset20DECI), maturity);
    }

    function testUnit_deploy1_20Decimals() public {
        console.log("deploy() reverts in constructor if a base asset with > 18 decimals is used");
        vm.expectRevert(stdError.arithmeticError); // underflows if deci > 18
        new Pool(address(shares462620DECI), address(fy20DECI), ts, g1Fee);
        // TODO: Add other pool types
    }

    function testUnit_deploy2_muIsZero() public {
        console.log("deploy() reverts in constructor if mu is zero");
        vm.expectRevert(abi.encodeWithSelector(MuCannotBeZero.selector));
        new Pool(address(shares4626DAI), address(fyDAI), ts, g1Fee);
        vm.expectRevert(abi.encodeWithSelector(MuCannotBeZero.selector));
        new Pool(address(shares4626USDC), address(fyUSDC), ts, g1Fee);
        // TODO: Add other pool types
    }

    function testUnit_deploy3_success() public {
        console.log("deploy() can successfully deploy a pool with proper constructor args");

        // set prices so mu is not zero
        setPrice(address(shares4626DAI), (muNumerator * (10**18)) / muDenominator);
        setPrice(address(shares4626USDC), (muNumerator * (10**6)) / muDenominator);

        new Pool(address(shares4626DAI), address(fyDAI), ts, g1Fee);
        new Pool(address(shares4626USDC), address(fyUSDC), ts, g1Fee);
        // TODO: Add other pool types
    }
}
