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

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../shared/Utils.sol";
import "../../shared/Constants.sol";

import "../../../Pool/PoolErrors.sol";
import {Math64x64} from "../../../Math64x64.sol";
import {YieldMath} from "../../../YieldMath.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "./State.sol";

contract SetFees is ZeroStateDai {
    using Math64x64 for uint256;

    function testUnit_setFees01() public {
        console.log("does not set invalid fee");

        uint16 g1Fee_ = 10001;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InvalidFee.selector, g1Fee_));
        pool.setFees(g1Fee_);
    }

    function testUnit_setFees02() public {
        console.log("does not set fee without auth");

        uint16 g1Fee_ = 9000;

        vm.prank(alice);
        vm.expectRevert("Access denied");
        pool.setFees(g1Fee_);
    }

    function testUnit_setFees03() public {
        console.log("sets valid fee");

        uint16 g1Fee_ = 8000;
        int128 expectedG1 = uint256(g1Fee_).divu(10000);
        int128 expectedG2 = uint256(10000).divu(g1Fee_);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit FeesSet(g1Fee_);

        pool.setFees(g1Fee_);

        assertEq(pool.g1(), expectedG1);
        assertEq(pool.g2(), expectedG2);
    }
}

contract Mint__ZeroState is ZeroStateDai {
    function testUnit_mint0() public {
        console.log("cannot mint before initialize or initialize without auth");

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_YVDAI);

        // Alice calls mint, but gets reverted.
        vm.expectRevert(abi.encodeWithSelector(NotInitialized.selector));
        vm.prank(alice);
        pool.mint(bob, bob, 0, MAX);

        // Setup new random user with no roles, and have them try to call init.
        address noAuth = payable(address(0xB0FFED));
        vm.expectRevert(bytes("Access denied"));
        vm.prank(noAuth);
        pool.init(bob);
    }

    function testUnit_mint1() public {
        console.log("adds initial liquidity");
        // Bob transfers some shares to the pool.
        vm.prank(bob);
        uint256 baseIn = pool.unwrapPreview(INITIAL_YVDAI);
        asset.mint(address(pool), baseIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            alice,
            bob,
            address(0),
            int256(-1 * int256(baseIn)),
            int256(0),
            int256(pool.mulMu(INITIAL_YVDAI))
        );

        // Alice calls init.
        vm.prank(alice);
        pool.init(bob);

        // Shares price is set to value of state variable cNumerator/cDenominator.
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);

        // Confirm balance of pool as expected, as well as cached balances.
        // First mint should equal shares in times mu
        require(pool.balanceOf(bob) == pool.mulMu(INITIAL_YVDAI));
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint2() public {
        console.log("adds liquidity with zero fyToken");

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_YVDAI);

        // Alice calls init.
        vm.startPrank(alice);
        pool.init(address(0));

        // After initializing, donate shares and sellFyToken to simulate having reached zero fyToken through trading
        shares.mint(address(pool), INITIAL_YVDAI);
        pool.sellFYToken(alice, 0);

        // Send more shares to the pool.
        shares.mint(address(pool), INITIAL_YVDAI);

        // Alice calls mint
        pool.mint(bob, bob, 0, MAX);

        // Confirm balance of pool as expected, as well as cached balances.
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 expectedLpTokens = (pool.totalSupply() * INITIAL_YVDAI) / sharesBal;
        require(pool.balanceOf(bob) == expectedLpTokens);
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    // Test intentionally ommitted.
    // function testUnit_mint3() public {
    //     console.log("syncs balances after donations");
}

contract Mint__WithLiquidity is WithLiquidityDAI {
    function testUnit_mint4() public {
        console.log("mints liquidity tokens, returning surplus");

        // Calculate expected Mint and SharesIn for 1 WAD fyToken in.
        uint256 fyTokenIn = WAD;
        uint256 expectedMint = (pool.totalSupply() * fyTokenIn) / fyToken.balanceOf(address(pool));
        uint256 expectedSharesIn = ((shares.balanceOf(address(pool)) * expectedMint) / pool.totalSupply());

        // send base for an extra wad of shares
        uint256 extraSharesIn = 1e18;
        uint256 expectedBaseIn = pool.unwrapPreview(expectedSharesIn + extraSharesIn);
        uint256 poolTokensBefore = pool.balanceOf(bob);

        // Send some base to the pool.
        asset.mint(address(pool), expectedBaseIn);
        // Send some fyToken to the pool.
        fyToken.mint(address(pool), fyTokenIn);

        // Alice calls mint to Bob.
        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        uint256 minted = pool.balanceOf(bob) - poolTokensBefore;

        // Confirm minted amount is as expected.  Check balances and caches.
        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(shares.balanceOf(bob), bobSharesInitialBalance, fyTokenIn / 10000);
        almostEqual(asset.balanceOf(bob), pool.getCurrentSharePrice(), fyTokenIn / 10000);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint5() public {
        console.log("cannot initialize twice");
        vm.expectRevert(abi.encodeWithSelector(Initialized.selector));

        // Alice calls init.
        vm.startPrank(alice);
        pool.init(address(0));
    }
}

contract Burn__WithLiquidity is WithLiquidityDAI {
    function testUnit_burn1() public {
        console.log("burns liquidity tokens");
        uint256 bobAssetBefore = asset.balanceOf(address(bob));
        uint256 sharesBalance = shares.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        address charlie = address(3);

        // Calculate expected shares and fytokens from the burn.
        uint256 expectedSharesOut = (lpTokensIn * sharesBalance) / poolSup;
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);

        uint256 expectedFYTokenOut = (lpTokensIn * fyTokenBalance) / poolSup;

        // Alice transfers in lp tokens then burns them.
        vm.prank(alice);
        pool.transfer(address(pool), lpTokensIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            alice,
            bob,
            charlie,
            int256(expectedAssetsOut),
            int256(expectedFYTokenOut),
            -int256(lpTokensIn)
        );

        // Alice calls burn.
        vm.prank(alice);
        pool.burn(bob, address(charlie), 0, MAX);

        // Confirm shares and fyToken out as expected and check balances pool and users.
        uint256 assetsOut = asset.balanceOf(address(bob)) - bobAssetBefore;
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        uint256 sharesOut = sharesBalance - shares.balanceOf(address(pool));
        almostEqual(sharesOut, expectedSharesOut, sharesOut / 10000);
        almostEqual(assetsOut, expectedAssetsOut, assetsOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}

contract MatureBurn_WithLiquidity is WithLiquidityDAI {
    function testUnit_matureBurn01() public {
        console.log("burns after maturity");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 lpTokensIn = poolBalBefore;

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 expectedSharesOut = (lpTokensIn * sharesReservesBefore) / pool.totalSupply();
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);
        // fyTokenOut = lpTokensIn * realFyTokenReserves / totalSupply
        uint256 expectedFyTokenOut = (lpTokensIn * (fyTokenReservesBefore - pool.totalSupply())) / pool.totalSupply();

        vm.warp(pool.maturity());
        vm.startPrank(alice);

        pool.transfer(address(pool), lpTokensIn);
        pool.burn(alice, alice, 0, uint128(MAX));

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, expectedSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut + lpTokensIn); // after burning, the reserves are updated to exclude the burned lp tokens
    }
}

contract MintWithBase__ZeroStateNonTv is ZeroStateDai {
    function testUnit_mintWithBase01() public {
        console.log("does not mintWithBase when pool is not initialized");

        vm.expectRevert(NotInitialized.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }
}

contract MintWithBase__WithLiquidity is WithLiquidityDAI {
    function testUnit_mintWithBase02() public {
        console.log("does not mintWithBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }

    function testUnit_mintWithBase03() public {
        console.log("mints with only base (asset)");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        // estimate how many shares need to be sold using arbitrary fyTokenToBuy amount and estimate lp tokens minted,
        // to be able to calculate how much asset to send to the pool
        uint128 fyTokenToBuy = uint128(1000 * 10**fyToken.decimals());
        uint128 assetsToSell = pool.buyFYTokenPreview(fyTokenToBuy);
        uint256 sharesToSell = pool.wrapPreview(assetsToSell);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 realFyTokenReserves = fyTokenReservesBefore - pool.totalSupply();

        uint256 fyTokenIn = fyToken.balanceOf(address(pool)) - realFyTokenReserves;
        // lpTokensMinted = totalSupply * (fyTokenToBuy + fyTokenIn) / realFyTokenReserves - fyTokenToBuy
        uint256 lpTokensMinted = (pool.totalSupply() * (fyTokenToBuy + fyTokenIn)) /
            (realFyTokenReserves - fyTokenToBuy);

        uint256 sharesIn = sharesToSell + ((sharesReservesBefore + sharesToSell) * lpTokensMinted) / pool.totalSupply();
        uint256 assetsIn = pool.unwrapPreview(sharesIn) + 2; // NOTE one wei issue: wrapping multiple times causes multiple one wei issue differences

        // mintWithBase
        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.mintWithBase(alice, alice, fyTokenToBuy, 0, uint128(MAX));

        // check user balances
        assertEq(assetBalBefore - asset.balanceOf(alice), assetsIn);
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

contract BurnForBase__WithLiquidity is WithLiquidityDAI {
    using Math64x64 for uint256;
    using Cast for uint256;
    using Cast for int128;

    function testUnit_burnForBase01() public {
        console.log("does not burnForBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.burnForBase(alice, 0, uint128(MAX));
    }

    function testUnit_burnForBase02() public {
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
            maturity - uint32(block.timestamp),
            k,
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
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut);
        assertEq(fyTokenBalBefore, fyToken.balanceOf(alice));
        assertEq(poolBalBefore - pool.balanceOf(alice), lpTokensToBurn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, totalSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, lpTokensToBurn);
    }
}
