// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

/*
  __     ___      _     _
  \ \   / (_)    | |   | | ████████╗███████╗███████╗████████╗███████╗
   \ \_/ / _  ___| | __| | ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    \   / | |/ _ \ |/ _` |    ██║   █████╗  ███████╗   ██║   ███████╗
     | |  | |  __/ | (_| |    ██║   ██╔══╝  ╚════██║   ██║   ╚════██║
     |_|  |_|\___|_|\__,_|    ██║   ███████╗███████║   ██║   ███████║
      yieldprotocol.com       ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚══════╝

*/

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//
//    NOTE:
//    These tests are setup on the PoolEuler contract instead of the Pool contract
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../Pool/PoolErrors.sol";
import {Math64x64} from "../../../../Math64x64.sol";
import {YieldMath} from "../../../../YieldMath.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";

import "../../../shared/Utils.sol";
import "../../../shared/Constants.sol";
import {ETokenMock} from "../../../mocks/ETokenMock.sol";
import "./State.sol";

contract Trade__WithLiquidityEulerDAI is WithLiquidityEulerDAI {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using Cast for uint256;

    function testUnit_Euler_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");

        uint256 fyTokenIn = 25_000 * 10**fyToken.decimals();
        uint256 assetBalanceBefore = asset.balanceOf(alice);
        uint256 fyTokenBalanceBefore = fyToken.balanceOf(alice);

        (uint104 sharesReserveBefore, uint104 fyTokenReserveBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            uint128(fyTokenIn) * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / pool.scaleFactor();
        uint256 expectedBaseOut = pool.unwrapPreview(expectedSharesOut);

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, int256(expectedBaseOut), -int256(fyTokenIn));

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.sellFYToken(alice, 0);

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalanceBefore, expectedBaseOut);
        assertEq(fyTokenBalanceBefore - fyToken.balanceOf(alice), fyTokenIn);

        // check pool reserves
        (uint104 sharesReserveAfter, uint104 fyTokenReserveAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReserveAfter, pool.getSharesBalance(), 1);
        assertApproxEqAbs(sharesReserveBefore - sharesReserveAfter, expectedSharesOut, 1);
        assertEq(fyTokenReserveAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReserveAfter - fyTokenReserveBefore, fyTokenIn);
    }

    function testUnit_Euler_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1 * 10**fyToken.decimals();
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellFYToken.selector,
                999785051469477285,
                340282366920938463463374607431768211455
            )
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_Euler_tradeDAI03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_Euler_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");

        uint128 sharesOut = uint128(1000 * 10**shares.decimals());
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            sharesOut * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / pool.scaleFactor();

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, int256(int128(assetsOut)), -int256(expectedFYTokenIn));

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), expectedFYTokenIn);
        pool.buyBase(alice, uint128(assetsOut), type(uint128).max);

        // check user balances
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1);
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), expectedFYTokenIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1);
        assertEq(sharesReservesBefore - sharesReservesAfter, sharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedFYTokenIn);
    }

    // Removed
    // function testUnit_Euler_tradeDAI05() public {

    function testUnit_Euler_tradeDAI06() public {
        console.log("buys base and retrieves change");

        uint128 assetsOut = uint128(1000 * 10**asset.decimals());
        uint256 sharesOut = pool.wrapPreview(assetsOut);
        uint128 expectedFyTokenIn = pool.buyBasePreview(assetsOut);
        uint128 surplusFyTokenIn = expectedFyTokenIn * 2;

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), surplusFyTokenIn); // transfer more than is required from the trade into the pool
        pool.buyBase(alice, assetsOut, uint128(MAX));

        // check user balances before retrieving
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1);
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), surplusFyTokenIn);

        pool.retrieveFYToken(alice);

        // check user balances after retrieving
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1);
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), expectedFyTokenIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, sharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedFyTokenIn);
    }
}

contract Trade__WithExtraFYTokenEulerDAI is WithExtraFYTokenEulerDAI {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using Cast for uint256;

    function testUnit_Euler_tradeDAI07() public {
        console.log("sells base (asset) for a certain amount of FYTokens");

        uint128 assetsIn = uint128(1000 * 10**asset.decimals());
        uint128 sharesIn = pool.wrapPreview(assetsIn).u128();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedFyTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            sharesIn * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / pool.scaleFactor();

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, -int128(assetsIn) - 1, int256(expectedFyTokenOut)); // NOTE one wei issue (assetsIn - 1)

        // trade
        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(alice, 0);

        // check user balances
        assertApproxEqAbs(assetBalBefore - asset.balanceOf(alice), assetsIn, 1); // NOTE one wei issue
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1); // NOTE one wei issue
        assertApproxEqAbs(sharesReservesAfter - sharesReservesBefore, sharesIn, 1); //  NOTE one wei issue
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut);
    }

    function testUnit_Euler_tradeDAI08() public {
        console.log("does not sell base beyond slippage");
        uint128 sharesIn = uint128(1000 * 10**shares.decimals());
        uint128 baseIn = pool.unwrapPreview(sharesIn).u128();
        asset.mint(address(pool), baseIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellBase.selector,
                1100212520384791756398,
                340282366920938463463374607431768211455
            )
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_Euler_tradeDAI09() public {
        console.log("donates fyToken and sells base");

        uint128 assetsIn = uint128(10000 * 10**asset.decimals());
        uint128 sharesIn = pool.wrapPreview(assetsIn).u128();
        uint128 fyTokenDonation = uint128(5000 * 10**fyToken.decimals());
        uint128 expectedFyTokenOut = pool.sellBasePreview(assetsIn);
        asset.mint(address(bob), assetsIn);

        // bob's balances
        uint256 assetBalBefore = asset.balanceOf(bob);
        uint256 fyTokenBalBefore = fyToken.balanceOf(bob);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // alice donates fyToken to the pool
        vm.prank(alice);
        fyToken.transfer(address(pool), fyTokenDonation);

        // bob trades
        vm.startPrank(bob);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(bob, 0);

        // check bob's balances
        assertEq(assetBalBefore - asset.balanceOf(bob), assetsIn);
        assertEq(fyToken.balanceOf(bob) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertApproxEqAbs(sharesReservesAfter - sharesReservesBefore, sharesIn, 1);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance() - fyTokenDonation); // the reserves should not take into consideration the donated fyToken
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut);
    }

    function testUnit_Euler_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base (asset)");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedSharesIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            fyTokenOut * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / pool.scaleFactor();
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn) + 1; // NOTE one wei issue

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, -int128(uint128(expectedAssetsIn)), int256(int128(fyTokenOut)));

        // trade
        vm.startPrank(alice);
        asset.transfer(address(pool), expectedAssetsIn);
        pool.buyFYToken(alice, fyTokenOut, uint128(MAX));

        // check user balances
        assertEq(assetBalBefore - asset.balanceOf(alice), expectedAssetsIn);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, fyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertApproxEqAbs(sharesReservesAfter - sharesReservesBefore, expectedSharesIn, 1); // NOTE one wei issue
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, fyTokenOut);
    }
}

contract Trade__PreviewFuncsDAI is WithExtraFYTokenEulerDAI {
    function testUnit_Euler_tradeDAI11() public {
        console.log("buyBase matches buyBasePreview");

        uint128 expectedAssetOut = uint128(1000 * 10**asset.decimals());
        uint128 fyTokenIn = pool.buyBasePreview(expectedAssetOut);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.buyBase(alice, expectedAssetOut, type(uint128).max);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertApproxEqAbs(assetBalAfter - assetBalBefore, expectedAssetOut, 1);
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }

    function testUnit_Euler_tradeDAI12() public {
        console.log("buyFYToken matches buyFYTokenPreview");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());
        uint256 expectedAssetsIn = pool.buyFYTokenPreview(fyTokenOut);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), expectedAssetsIn);
        pool.buyFYToken(alice, fyTokenOut, type(uint128).max);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, expectedAssetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, fyTokenOut);
    }

    function testUnit_Euler_tradeDAI13() public {
        console.log("sellBase matches sellBasePreview");

        uint128 assetsIn = uint128(1000 * 10**asset.decimals());
        uint256 expectedFyToken = pool.sellBasePreview(assetsIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(alice, 0);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, assetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, expectedFyToken);
    }

    function testUnit_Euler_tradeDAI14() public {
        console.log("sellFYToken matches sellFYTokenPreview");

        uint128 fyTokenIn = uint128(1000 * 10**fyToken.decimals());
        uint128 expectedAsset = pool.sellFYTokenPreview(fyTokenIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.sellFYToken(alice, 0);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertApproxEqAbs(assetBalAfter - assetBalBefore, expectedAsset, 1);
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }
}
