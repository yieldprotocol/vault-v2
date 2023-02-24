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
//    Mainnet fork tests using December 2022 DAI pool
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../../Pool/PoolErrors.sol";
import {Math64x64} from "../../../../../Math64x64.sol";
import {YieldMath} from "../../../../../YieldMath.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";

import "../../../../shared/Utils.sol";
import "../../../../shared/Constants.sol";
import "./State.sol";

contract Trade__WithLiquidityEulerDAIFork is EulerDAIFork {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using Cast for uint256;

    function testForkUnit_Euler_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");

        uint256 fyTokenIn = 10_000 * 10**fyToken.decimals();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        uint256 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReservesBefore,
            fyTokenReservesBefore,
            uint128(fyTokenIn),
            pool.maturity() - uint32(block.timestamp),
            pool.ts(),
            pool.g2(),
            pool.getC(),
            pool.mu()
        );
        uint256 expectedBaseOut = pool.unwrapPreview(expectedSharesOut);

        vm.expectEmit(true, true, false, true);
        emit Trade(pool.maturity(), alice, alice, int256(expectedBaseOut), -int256(fyTokenIn));

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.sellFYToken(alice, 0);

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedBaseOut);
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), fyTokenIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, expectedSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, fyTokenIn);
    }

    function testForkUnit_Euler_tradeDAI02() public {
        console.log("buys a certain amount base for fyToken");

        uint128 assetsOut = uint128(1000 * 10**asset.decimals());
        uint128 sharesOut = pool.wrapPreview(assetsOut).u128();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReservesBefore,
            fyTokenReservesBefore,
            sharesOut,
            pool.maturity() - uint32(block.timestamp),
            pool.ts(),
            pool.g2(),
            pool.getC(),
            pool.mu()
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(pool.maturity(), alice, alice, int256(int128(assetsOut)), -int256(expectedFYTokenIn));

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), expectedFYTokenIn);
        pool.buyBase(alice, uint128(assetsOut), type(uint128).max);

        // check user balances
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1); // NOTE one wei issue
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), expectedFYTokenIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, sharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedFYTokenIn);
    }

    function testForkUnit_Euler_tradeDAI03() public {
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
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1); // NOTE one wei issue
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), surplusFyTokenIn);

        pool.retrieveFYToken(alice);

        // check user balances after retrieving
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1); // NOTE one wei issue
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), expectedFyTokenIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, sharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedFyTokenIn);
    }
}

contract Trade__WithExtraFYTokenEulerDAIFork is EulerDAIFork {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using Cast for uint256;

    function testForkUnit_Euler_tradeExtraDAI01() public {
        console.log("sells base (asset) for a certain amount of FYTokens");

        uint128 assetsIn = uint128(1000 * 10**asset.decimals());
        uint128 sharesIn = pool.wrapPreview(assetsIn).u128();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        uint256 expectedFyTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReservesBefore,
            fyTokenReservesBefore,
            sharesIn,
            pool.maturity() - uint32(block.timestamp),
            pool.ts(),
            pool.g1(),
            pool.getC(),
            pool.mu()
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(pool.maturity(), alice, alice, -int256(int128(assetsIn - 1)), int256(expectedFyTokenOut)); // NOTE one wei issue (assetsIn - 1)

        // trade
        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(alice, 0);

        // check user balances
        assertEq(assetBalBefore - asset.balanceOf(alice), assetsIn);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesAfter - sharesReservesBefore, sharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut);
    }

    function testForkUnit_Euler_tradeExtraDAI02() public {
        console.log("donates fyToken and sells base");

        uint128 assetsIn = uint128(10_000 * 10**asset.decimals());
        uint128 sharesIn = pool.wrapPreview(assetsIn).u128();
        uint128 fyTokenDonation = uint128(5_000 * 10**fyToken.decimals());
        uint128 expectedFyTokenOut = pool.sellBasePreview(assetsIn);

        vm.startPrank(alice);
        asset.transfer(address(bob), assetsIn);

        // bob's balances
        uint256 assetBalBefore = asset.balanceOf(bob);
        uint256 fyTokenBalBefore = fyToken.balanceOf(bob);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // alice donates fyToken to the pool
        fyToken.transfer(address(pool), fyTokenDonation);
        vm.stopPrank();

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
        assertEq(sharesReservesAfter - sharesReservesBefore, sharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance() - fyTokenDonation); // the reserves should not take into consideration the donated fyToken
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut);
    }

    function testForkUnit_Euler_tradeExtraDAI03() public {
        console.log("buys a certain amount of fyTokens with base (asset)");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        uint256 expectedSharesIn = YieldMath.sharesInForFYTokenOut(
            sharesReservesBefore,
            fyTokenReservesBefore,
            fyTokenOut,
            pool.maturity() - uint32(block.timestamp),
            pool.ts(),
            pool.g1(),
            pool.getC(),
            pool.mu()
        );
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn) + 1; // NOTE one wei issue

        vm.expectEmit(true, true, false, true);
        emit Trade(pool.maturity(), alice, alice, -int256(expectedAssetsIn - 1), int256(int128(fyTokenOut))); // NOTE one wei issue (expectedAssetsIn - 1)

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
        assertEq(sharesReservesAfter - sharesReservesBefore, expectedSharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, fyTokenOut);
    }
}

contract Trade__PreviewFuncsDAIFork is EulerDAIFork {
    function testForkUnit_Euler_tradePreviewsDAI01() public {
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

        assertApproxEqAbs(assetBalAfter - assetBalBefore, expectedAssetOut, 1); // NOTE one wei issue
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }

    function testForkUnit_Euler_tradePreviewsDAI02() public {
        console.log("buyFYToken matches buyFYTokenPreview");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());
        uint256 expectedAssetsIn = pool.buyFYTokenPreview(fyTokenOut) + 1; // NOTE we add one wei here to prevent reverts within buyFYToken (known one wei issue)

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

    function testForkUnit_Euler_tradePreviewsDAI03() public {
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

    /* NOTE currently fails (known issue)
     * sellFYTokenPreview on mainnet currently outputs (inaccurately) a shares amount
     * this has now been updated to (correctly) output base amount in Pool.sol
     * the current dai/usdc december 2022 mainnet pools will continue to incorrectly output shares amounts, whereas future pools will reflect the update
     */
    function testForkUnit_Euler_tradePreviewsDAI04() public {
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

        assertApproxEqAbs(assetBalAfter - assetBalBefore, expectedAsset, 1); // NOTE one wei issue
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }
}

contract Trade__CheckSharePrice is EulerDAIFork {
    function testForkUnit_Euler_tradeSharePriceDAI01() public {
        console.log("currentSharePrice matches external contract share price");

        uint256 eTokenPrice = eToken.convertBalanceToUnderlying(WAD);
        assertEq(pool.getCurrentSharePrice(), eTokenPrice);
    }

    function testForkUnit_Euler_tradeSharePriceDAI02() public {
        console.log("currentSharePrice is not relative to the amount provided");

        uint256 currentSharePrice = pool.getCurrentSharePrice();
        uint256 eTokenPrice = eToken.convertBalanceToUnderlying(WAD * 1_000) / 1000;
        uint256 eTokenPriceGreater = eToken.convertBalanceToUnderlying(WAD * 1_000_000) / 1_000_000;
        uint256 eTokenPriceGreatest = eToken.convertBalanceToUnderlying(WAD * 1_000_000_000) / 1_000_000_000;

        assertEq(currentSharePrice, eTokenPrice);
        assertEq(currentSharePrice, eTokenPriceGreater);
        assertEq(currentSharePrice, eTokenPriceGreatest);
    }

    function testForkUnit_Euler_tradeSharePriceDAI03() public {
        console.log("currentSharePrice matches unwrapPreview");

        uint256 currentSharePrice = pool.getCurrentSharePrice();
        uint256 unwrapPreview = pool.unwrapPreview(WAD);

        assertEq(currentSharePrice, unwrapPreview);
    }
}
