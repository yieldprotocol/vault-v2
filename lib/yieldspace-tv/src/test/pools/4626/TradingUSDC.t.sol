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

import "../../../Pool/PoolErrors.sol";
import {Math64x64} from "../../../Math64x64.sol";
import {YieldMath} from "../../../YieldMath.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";

import {almostEqual, setPrice} from "../../shared/Utils.sol";
import {IERC4626Mock} from "../../mocks/ERC4626TokenMock.sol";
import "../../shared/Constants.sol";
import {FYTokenMock} from "../../mocks/FYTokenMock.sol";
import "./State.sol";

contract TradeUSDC__WithLiquidity is WithLiquidityUSDC {
    using Math64x64 for uint256;
    using Math64x64 for int128;
    using Cast for uint256;

    function testUnit_tradeUSDC01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e6;

        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e6;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellFYToken.selector, 999784, 340282366920938463463374607431768211455)
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_tradeUSDC03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_tradeUSDC04() public {
        console.log("buys a certain amount base for fyToken");
        (, uint104 fyTokenBalBefore, , ) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);
        uint128 sharesOut = uint128(1000 * 1e6);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e6).fromUInt()
        );

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves * 1e12,
            virtFYTokenBal * 1e12,
            sharesOut * 1e12,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / 1e12;

        vm.prank(bob);
        pool.buyBase(bob, assetsOut, type(uint128).max);

        (, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut));

        almostEqual(fyTokenIn, expectedFYTokenIn, 1);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_tradeUSDC05() public {

    function testUnit_tradeUSDC06() public {
        console.log("buys base and retrieves change");
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 aliceFYTokenBefore = fyToken.balanceOf(alice);
        uint128 sharesOut = uint128(1e6);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        fyToken.mint(address(pool), initialFYTokens);

        vm.prank(alice);
        pool.buyBase(bob, assetsOut, uint128(MAX));
        require(shares.balanceOf(bob) == bobSharesBefore);
        require(asset.balanceOf(bob) == bobAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut));

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        vm.prank(alice);
        pool.retrieveFYToken(alice);

        require(fyToken.balanceOf(alice) > aliceFYTokenBefore);
    }

    function testUnit_tradeUSDC13() public {
        console.log("buys ALL base and retrieves change");
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 bobFYTokensBefore = fyToken.balanceOf(bob);

        uint128 maxBaseOut = pool.maxBaseOut();
        assertEq(maxBaseOut, 1087790.901304e6);
        uint128 requiredFYTokens = pool.buyBasePreview(maxBaseOut);

        // I'll mint what's required + an extra tenner to test the retrieve method
        fyToken.mint(address(pool), requiredFYTokens + 10e6);
        uint128 fyTokenIn = pool.buyBase(bob, maxBaseOut, type(uint128).max);

        // I should have paid the quoted amount
        assertEq(fyTokenIn, requiredFYTokens);
        // I should have got the max (rounding error allowed)
        assertEq(asset.balanceOf(bob), bobAssetBefore + maxBaseOut - 1);

        // I'll retrieve the extra 10 USDC I minted on purpose
        pool.retrieveFYToken(bob);
        assertEq(fyToken.balanceOf(bob), bobFYTokensBefore + 10e6);

        // I can't buy more from the pool
        assertEq(pool.maxBaseOut(), 1);
        vm.expectRevert("YieldMath: Too many shares in");
        pool.buyBasePreview(3);
    }

    function testUnit_tradeUSDC14() public {
        console.log("sells ALL fyToken");
        uint256 bobAssetBefore = asset.balanceOf(bob);

        uint128 maxFYTokenIn = pool.maxFYTokenIn();
        assertEq(maxFYTokenIn, 1089539.972626e6);
        uint128 expectedBaseOut = pool.sellFYTokenPreview(maxFYTokenIn);

        // I'll mint what's required, can't mint extra as I'm dealing on the max
        fyToken.mint(address(pool), maxFYTokenIn);
        uint128 baseOut = pool.sellFYToken(bob, 0);

        // I should have got the max
        assertEq(baseOut, expectedBaseOut);
        assertEq(asset.balanceOf(bob), bobAssetBefore + baseOut);

        // I can't sell more to the pool
        assertEq(pool.maxFYTokenIn(), 1);
        vm.expectRevert("YieldMath: Rate overflow (yxa)");
        pool.sellFYTokenPreview(2);
    }

    function testUnit_tradeUSDC15() public {
        console.log("sells ALL base");
        uint256 bobFYTokensBefore = fyToken.balanceOf(bob);

        uint128 maxBaseIn = pool.maxBaseIn();
        assertEq(maxBaseIn, 122209.753345e6);
        uint128 expectedFYTokenOut = pool.sellBasePreview(maxBaseIn);

        // I'll mint what's required, can't mint extra as I'm dealing on the max
        asset.mint(address(pool), maxBaseIn);
        uint128 fyTokenOut = pool.sellBase(bob, 0);

        // I should have got the max (rounding error allowed)
        assertEq(fyTokenOut, expectedFYTokenOut);
        assertEq(fyToken.balanceOf(bob), bobFYTokensBefore + fyTokenOut);

        // I can't sell more to the pool
        assertEq(pool.maxBaseIn(), 1);
        vm.expectRevert(
            abi.encodeWithSelector(NegativeInterestRatesNotAllowed.selector, 1155000.624893e6, 1155000.624895e6)
        );
        pool.sellBasePreview(4);
    }

    function testUnit_tradeUSDC16() public {
        console.log("buys ALL fyTokens and retrieves change");
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 bobFYTokensBefore = fyToken.balanceOf(bob);

        uint128 maxFYTokenOut = pool.maxFYTokenOut();
        assertEq(maxFYTokenOut, 122221.597326e6);
        uint128 requiredBase = pool.buyFYTokenPreview(maxFYTokenOut);

        // I'll mint what's required + an extra tenner to test the retrieve method
        asset.mint(address(pool), requiredBase + 10e6);
        uint128 baseIn = pool.buyFYToken(bob, maxFYTokenOut, type(uint128).max);

        // I should have paid the quoted amount
        assertEq(baseIn, requiredBase);
        // I should have got the max
        assertEq(fyToken.balanceOf(bob), bobFYTokensBefore + maxFYTokenOut);

        // I'll retrieve the extra 10 USDC I minted on purpose (converted into shares)
        pool.retrieveShares(bob);
        assertEq(shares.balanceOf(bob), bobSharesBefore + 9.090908e6);

        // I can't buy more from the pool
        assertEq(pool.maxFYTokenOut(), 1);
        vm.expectRevert(
            abi.encodeWithSelector(NegativeInterestRatesNotAllowed.selector, 1155000.624892e6, 1155000.624894e6)
        );
        pool.buyFYTokenPreview(3);
    }
}

contract TradeUSDC__WithExtraFYToken is WithExtraFYTokenUSDC {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_tradeUSDC07() public {
        uint128 sharesIn = uint128(25000 * 1e6);
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint256 userSharesBalanceBefore = shares.balanceOf(alice);
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e6).fromUInt()
        );

        // Transfer shares for sale to the pool
        shares.mint(address(pool), sharesIn);
        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves * 1e12,
            virtFYTokenBal * 1e12,
            sharesIn * 1e12,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / 1e12;

        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(shares.balanceOf(alice) == userSharesBalanceBefore, "'From' wallet should have no shares tokens");
        require(fyTokenOut == expectedFYTokenOut);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC08() public {
        console.log("does not sell base beyond slippage");
        uint128 sharesIn = uint128(1e6);
        uint128 assetsIn = uint128(pool.unwrapPreview(sharesIn));
        asset.mint(address(pool), assetsIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100213, 340282366920938463463374607431768211455)
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeUSDC09() public {
        console.log("donating fyToken does not affect cache balances when selling base");
        uint128 baseIn = uint128(1e6);
        uint128 fyTokenDonation = uint128(1e6);

        fyToken.mint(address(pool), fyTokenDonation);
        asset.mint(address(pool), baseIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_tradeUSDC10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint104 sharesCachedBefore, , , ) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(1e6);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e6).fromUInt()
        );

        // Transfer shares for sale to the pool
        asset.mint(address(pool), pool.unwrapPreview(initialShares));

        uint256 expectedSharesIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            virtFYTokenBal,
            fyTokenOut,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent, , ) = pool.getCache();

        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;
        uint256 sharesChange = pool.getSharesBalance() - sharesCachedCurrent;

        require(fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut, "'User2' wallet should have 1 fyToken token");

        almostEqual(sharesIn, expectedSharesIn, sharesIn / 100000);
        require(sharesCachedCurrent + sharesChange == pool.getSharesBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_tradeUSDC11() public {

    function testUnit_tradeUSDC12() public {
        console.log("donates shares and buys fyToken");
        uint256 sharesBalances = pool.getSharesBalance();
        uint256 fyTokenBalances = pool.getFYTokenBalance();
        (uint104 sharesCachedBefore, , , ) = pool.getCache();

        uint128 fyTokenOut = uint128(1e6);
        uint128 sharesDonation = uint128(1e6);

        shares.mint(address(pool), initialShares + sharesDonation);

        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent, , ) = pool.getCache();
        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;

        require(sharesCachedCurrent == sharesBalances + sharesIn);
        require(fyTokenCachedCurrent == fyTokenBalances - fyTokenOut);
    }
}

contract TradeUSDCPreviews__WithExtraFYToken is WithExtraFYTokenUSDC {
    function testUnit_tradeUSDC13() public {
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

    // getting one wei difference between expected fyToken out
    // causing revert within trade func
    function testUnit_tradeUSDC14() public {
        console.log("buyFYToken matches buyFYTokenPreview");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());
        uint256 expectedAssetsIn = pool.buyFYTokenPreview(fyTokenOut) + 1; // NOTE one wei issue

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

    function testUnit_tradeUSDC15() public {
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

    function testUnit_tradeUSDC16() public {
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

contract Trade__InvariantUSDC is WithMoreLiquidityUSDC {
    function testUnit_tradeInvariantUSDC01() public {
        console.log("buyBase, then check the invariant didn't go down");

        uint128 invariantBefore = pool.invariant();

        vm.startPrank(alice);

        for (uint256 i; i < 1000; i++) {
            uint128 expectedAssetOut = uint128(1000 * 10**asset.decimals());
            uint128 fyTokenIn = pool.buyBasePreview(expectedAssetOut);
            fyToken.transfer(address(pool), fyTokenIn);
            pool.buyBase(alice, expectedAssetOut, type(uint128).max);
        }

        assertGe(pool.invariant(), invariantBefore);
    }

    function testUnit_tradeInvariantUSDC02() public {
        console.log("buyFYToken, then check the invariant didn't go down");

        uint128 invariantBefore = pool.invariant();

        vm.startPrank(alice);

        for (uint256 i; i < 1000; i++) {
            uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());
            uint256 expectedAssetsIn = pool.buyFYTokenPreview(fyTokenOut) + 1; // NOTE one wei issue
            asset.transfer(address(pool), expectedAssetsIn);
            pool.buyFYToken(alice, fyTokenOut, type(uint128).max);
        }

        assertGe(pool.invariant(), invariantBefore);
    }

    function testUnit_tradeInvariantUSDC03() public {
        console.log("sellBase, then check the invariant didn't go down");

        uint128 invariantBefore = pool.invariant();

        vm.startPrank(alice);

        for (uint256 i; i < 1000; i++) {
            uint128 assetsIn = uint128(1000 * 10**asset.decimals());
            asset.transfer(address(pool), assetsIn);
            pool.sellBase(alice, 0);
        }

        assertGe(pool.invariant(), invariantBefore);
    }

    function testUnit_tradeInvariantUSDC04() public {
        console.log("sellFYToken, then check the invariant didn't go down");

        uint128 invariantBefore = pool.invariant();

        vm.startPrank(alice);

        for (uint256 i; i < 1000; i++) {
            uint128 fyTokenIn = uint128(1000 * 10**fyToken.decimals());
            fyToken.transfer(address(pool), fyTokenIn);
            pool.sellFYToken(alice, 0);
        }

        assertGe(pool.invariant(), invariantBefore);
    }
}
