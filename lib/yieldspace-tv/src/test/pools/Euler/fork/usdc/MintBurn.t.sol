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
//    Mainnet fork tests using December 2022 USDC pool
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../../Pool/PoolErrors.sol";
import {IPool, IERC20Like as IERC20Metadata} from "../../../../../Pool/PoolImports.sol";
import {Math64x64} from "../../../../../Math64x64.sol";
import {YieldMath} from "../../../../../YieldMath.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";

import "../../../../shared/Utils.sol";
import "../../../../shared/Constants.sol";
import "./State.sol";

contract SetFeesEulerUSDCFork is EulerUSDCFork {
    using Math64x64 for uint256;

    function testForkUnit_Euler_setFeesUSDC01() public {
        console.log("does not set invalid fee");

        uint16 g1Fee_ = 10001;

        vm.prank(timelock);
        vm.expectRevert(abi.encodeWithSelector(InvalidFee.selector, g1Fee_));
        pool.setFees(g1Fee_);
    }

    function testForkUnit_Euler_setFeesUSDC02() public {
        console.log("does not set fee without auth");

        uint16 g1Fee_ = 9000;

        vm.prank(alice);
        vm.expectRevert("Access denied");
        pool.setFees(g1Fee_);
    }

    function testForkUnit_Euler_setFeesUSDC03() public {
        console.log("sets valid fee");

        uint16 g1Fee_ = 8000;
        int128 expectedG1 = uint256(g1Fee_).divu(10000);
        int128 expectedG2 = uint256(10000).divu(g1Fee_);

        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit FeesSet(g1Fee_);

        pool.setFees(g1Fee_);

        assertEq(pool.g1(), expectedG1);
        assertEq(pool.g2(), expectedG2);
    }
}

contract Mint__WithLiquidityEulerUSDCFork is EulerUSDCForkSkewedReserves {
    function testForkUnit_Euler_mintUSDC03() public {
        console.log("mints liquidity tokens, returning shares surplus converted to asset");

        uint256 fyTokenIn = 1 * 10**fyToken.decimals(); // NOTE had to change this to be less than 1000 because of the reserves ratio
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 realFyTokenReserves = fyTokenReservesBefore - pool.totalSupply();

        // lpTokensMinted = totalSupply * fyTokenIn / realFyTokenReserves
        uint256 expectedMint = (pool.totalSupply() * fyTokenIn) / realFyTokenReserves;
        // expectedSharesIn = sharesReserves * lpTokensMinted / totalSupply
        uint256 expectedSharesIn = (sharesReservesBefore * expectedMint) / pool.totalSupply();
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn);

        // pool mint
        vm.startPrank(alice);
        asset.transfer(address(pool), expectedAssetsIn * 2); // alice sends too many assets
        fyToken.transfer(address(pool), fyTokenIn);
        pool.mint(alice, alice, 0, MAX);

        // check user balances
        assertApproxEqAbs(assetBalBefore - asset.balanceOf(alice), expectedAssetsIn, 3); // NOTE one wei issue; also, alice sent too many assets, but still gets back surplus
        assertApproxEqAbs(fyTokenBalBefore - fyToken.balanceOf(alice), fyTokenIn, 1);
        assertApproxEqAbs(pool.balanceOf(alice) - poolBalBefore, expectedMint, 1);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1);
        assertApproxEqAbs(sharesReservesAfter - sharesReservesBefore, expectedSharesIn, 1);
        assertApproxEqAbs(fyTokenReservesAfter, pool.getFYTokenBalance(), 1);
        assertApproxEqAbs(fyTokenReservesAfter - fyTokenReservesBefore, fyTokenIn + expectedMint, 1);
    }
}

contract Burn__WithLiquidityEulerUSDCFork is EulerUSDCForkWithLiquidity {
    function testForkUnit_Euler_burnUSDC01() public {
        console.log("burns liquidity tokens");

        uint256 lpTokensIn = 1000 * 10**asset.decimals(); // using asset decimals here, since they match the pool
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 expectedSharesOut = (lpTokensIn * sharesReservesBefore) / pool.totalSupply();
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);
        uint256 expectedFyTokenOut = (lpTokensIn * (fyTokenReservesBefore - pool.totalSupply())) / pool.totalSupply();

        vm.startPrank(alice);
        pool.transfer(address(pool), lpTokensIn);

        // burn
        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            pool.maturity(),
            alice,
            alice,
            alice,
            int256(expectedAssetsOut),
            int256(expectedFyTokenOut),
            -int256(lpTokensIn)
        );
        pool.burn(alice, alice, 0, MAX);

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);
        assertEq(poolBalBefore - pool.balanceOf(alice), lpTokensIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, expectedSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut + lpTokensIn);
    }
}

contract MatureBurn_WithLiquidityEulerUSDCFork is EulerUSDCForkSkewedReserves {
    function testForkUnit_Euler_matureBurnUSDC01() public {
        console.log("burns after maturity");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 lpTokensIn = poolBalBefore;

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // after maturity
        vm.warp(pool.maturity());

        // fyTokenOut = lpTokensIn * realFyTokenReserves / totalSupply
        uint256 expectedFyTokenOut = (lpTokensIn * (fyTokenReservesBefore - pool.totalSupply())) / pool.totalSupply();
        uint256 expectedSharesOut = (lpTokensIn * sharesReservesBefore) / pool.totalSupply();
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);

        vm.startPrank(alice);

        pool.transfer(address(pool), lpTokensIn);
        pool.burn(alice, alice, 0, uint128(MAX));

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1);
        assertEq(sharesReservesBefore - sharesReservesAfter, expectedSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut + lpTokensIn); // after burning, the reserves are updated to exclude the burned lp tokens
    }
}

contract MintWithBase__WithLiquidityEulerUSDCFork is EulerUSDCForkSkewedReserves {
    function testForkUnit_Euler_mintWithBaseUSDC01() public {
        console.log("does not mintWithBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }

    function testForkUnit_Euler_mintWithBaseUSDC02() public {
        console.log("mints with only base (asset)");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        // estimate how many shares need to be sold using arbitrary fyTokenToBuy amount and estimate lp tokens minted,
        // to be able to calculate how much asset to send to the pool
        uint128 fyTokenToBuy = uint128(100 * 10**fyToken.decimals());
        uint128 assetsToSell = pool.buyFYTokenPreview(fyTokenToBuy) + 2; // NOTE we add two wei here to prevent reverts within buyFYToken (known one wei issue)
        uint256 sharesToSell = pool.wrapPreview(assetsToSell);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 realFyTokenReserves = fyTokenReservesBefore - pool.totalSupply();

        // lpTokensMinted = totalSupply * (fyTokenToBuy + fyTokenIn) / realFyTokenReserves - fyTokenToBuy
        uint256 lpTokensMinted = (pool.totalSupply() * (fyTokenToBuy + 0)) / (realFyTokenReserves - fyTokenToBuy);

        uint256 sharesIn = sharesToSell + ((sharesReservesBefore + sharesToSell) * lpTokensMinted) / pool.totalSupply();
        uint256 assetsIn = pool.unwrapPreview(sharesIn);

        // mintWithBase
        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.mintWithBase(alice, alice, fyTokenToBuy, 0, uint128(MAX));

        // check user balances
        assertApproxEqAbs(assetBalBefore - asset.balanceOf(alice), assetsIn, 3); // NOTE one wei issue
        assertEq(fyTokenBalBefore, fyToken.balanceOf(alice));
        assertEq(pool.balanceOf(alice) - poolBalBefore, lpTokensMinted);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertApproxEqAbs(sharesReservesAfter - sharesReservesBefore, sharesIn, 1); // NOTE one wei issue
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, lpTokensMinted);
    }
}

contract BurnForBase__WithLiquidityEulerUSDCFork is EulerUSDCForkWithLiquidity {
    using Math64x64 for uint256;
    using Cast for uint256;

    function testForkUnit_Euler_burnForBaseUSDC01() public {
        console.log("does not burnForBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.burnForBase(alice, 0, uint128(MAX));
    }

    function testForkUnit_Euler_burnForBaseUSDC02() public {
        console.log("burns for only base (asset)");

        // using a value that we assume will be below maxSharesOut and maxFYTokenOut, and will allow for trading to base
        uint256 lpTokensToBurn = 1000 * 10**asset.decimals(); // using the asset decimals, since they match the pool

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // estimate how many shares and fyToken we will get back from burn
        uint256 sharesOut = (lpTokensToBurn * sharesReservesBefore) / pool.totalSupply();
        // fyTokenOut = lpTokensBurned * realFyTokenReserves / totalSupply
        uint256 fyTokenOut = (lpTokensToBurn * (fyTokenReservesBefore - pool.totalSupply())) / pool.totalSupply();

        // estimate how much shares (and base) we can trade fyToken for, using the new pool state
        uint256 fyTokenOutToShares = YieldMath.sharesOutForFYTokenIn(
            (sharesReservesBefore - sharesOut).u128(),
            (fyTokenReservesBefore - fyTokenOut).u128(),
            fyTokenOut.u128(),
            pool.maturity() - uint32(block.timestamp),
            pool.ts(),
            pool.g2(),
            pool.getC(),
            pool.mu()
        );
        uint256 totalSharesOut = sharesOut + fyTokenOutToShares;
        uint256 expectedAssetsOut = pool.unwrapPreview(totalSharesOut);

        // burnForBase
        vm.startPrank(alice);
        pool.transfer(address(pool), lpTokensToBurn);

        pool.burnForBase(alice, 0, uint128(MAX));

        // check user balances
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut, 5); // NOTE one wei issue
        assertApproxEqAbs(fyTokenBalBefore, fyToken.balanceOf(alice), 5);
        assertApproxEqAbs(poolBalBefore - pool.balanceOf(alice), lpTokensToBurn, 5);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 5); // NOTE one wei issue
        assertApproxEqAbs(sharesReservesBefore - sharesReservesAfter, totalSharesOut, 5); // NOTE one wei issue
        assertApproxEqAbs(fyTokenReservesAfter, pool.getFYTokenBalance(), 5);
        assertApproxEqAbs(fyTokenReservesBefore - fyTokenReservesAfter, lpTokensToBurn, 5);
    }
}
