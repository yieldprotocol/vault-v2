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

contract TradeDAI__WithLiquidity is WithLiquidityDAI {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using Cast for uint256;

    function testUnit_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Send some fyToken to pool and calculate expectedSharesOut
        uint256 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            virtFYTokenBal,
            uint128(fyTokenIn),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );

        uint256 expectedBaseOut = pool.unwrapPreview(expectedSharesOut);
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, int256(expectedBaseOut), -int256(fyTokenIn));

        // Alice calls sellFYToken.
        fyToken.mint(address(pool), fyTokenIn);
        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        // Confirm cached balances are updated properly.
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;

        // Send 1 WAD fyToken to pool.
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellFYToken.selector,
                999785054771931334,
                340282366920938463463374607431768211455
            )
        );
        // Set minRatio to uint128.max and see it get reverted.
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_tradeDAI03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");
        (, uint104 fyTokenBalBefore, , ) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);

        uint128 sharesOut = uint128(WAD);
        uint128 baseOut = pool.unwrapPreview(sharesOut).u128();

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Send some fyTokens to the pool and see fyTokenIn is as expected.
        fyToken.mint(address(pool), initialFYTokens);

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            virtFYTokenBal,
            sharesOut,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, bob, bob, int256(int128(baseOut)), -int256(expectedFYTokenIn));

        // Bob calls buyBase
        vm.prank(bob);
        pool.buyBase(bob, uint128(baseOut), type(uint128).max);

        // Check cached balances are udpated correctly.
        (, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut));

        almostEqual(fyTokenIn, expectedFYTokenIn, sharesOut / 1000000);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_tradeDAI05() public {

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_tradeDAI06() public {
    //     console.log("when buying shares, donating fyToken and extra shares doesn't get absorbed and the shares is unwrapped and sent back");

    function testUnit_tradeDAI13() public {
        console.log("buys ALL base and retrieves change");
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 bobFYTokensBefore = fyToken.balanceOf(bob);

        uint128 maxBaseOut = pool.maxBaseOut();
        assertEq(maxBaseOut, 1087790.901202388886334554e18);
        uint128 requiredFYTokens = pool.buyBasePreview(maxBaseOut);

        // I'll mint what's required + an extra tenner to test the retrieve method
        fyToken.mint(address(pool), requiredFYTokens + 10e18);
        uint128 fyTokenIn = pool.buyBase(bob, maxBaseOut, type(uint128).max);

        // I should have paid the quoted amount
        assertEq(fyTokenIn, requiredFYTokens);
        // I should have got the max (rounding error allowed)
        assertEq(asset.balanceOf(bob), bobAssetBefore + maxBaseOut - 1);

        // I'll retrieve the extra 10 DAI I minted on purpose
        pool.retrieveFYToken(bob);
        assertEq(fyToken.balanceOf(bob), bobFYTokensBefore + 10e18);

        // I can't buy more from the pool
        assertEq(pool.maxBaseOut(), 1);
        vm.expectRevert("YieldMath: Too many shares in");
        pool.buyBasePreview(3);
    }

    function testUnit_tradeDAI14() public {
        console.log("sells ALL fyToken");
        uint256 bobAssetBefore = asset.balanceOf(bob);

        uint128 maxFYTokenIn = pool.maxFYTokenIn();
        assertEq(maxFYTokenIn, 1089539.945494126677240200e18);
        uint128 expectedBaseOut = pool.sellFYTokenPreview(maxFYTokenIn);

        // I'll mint what's required, can't mint extra as I'm dealing on the max
        fyToken.mint(address(pool), maxFYTokenIn);
        uint128 baseOut = pool.sellFYToken(bob, 0);

        // I should have got the max
        assertEq(baseOut, expectedBaseOut);
        assertEq(asset.balanceOf(bob), bobAssetBefore + baseOut);

        // I can't sell more to the pool
        assertEq(pool.maxFYTokenIn(), 0);
        vm.expectRevert("YieldMath: Rate overflow (yxa)");
        pool.sellFYTokenPreview(10e8); // Super low value in DAI
    }

    function testUnit_tradeDAI15() public {
        console.log("sells ALL base");
        uint256 bobFYTokensBefore = fyToken.balanceOf(bob);

        uint128 maxBaseIn = pool.maxBaseIn();
        assertEqDecimal(maxBaseIn, 122209.753490274010000000e18, 18);
        uint128 expectedFYTokenOut = pool.sellBasePreview(maxBaseIn);

        // I'll mint what's required, can't mint extra as I'm dealing on the max
        asset.mint(address(pool), maxBaseIn);
        uint128 fyTokenOut = pool.sellBase(bob, 0);

        // I should have got the max (rounding error allowed)
        assertEq(fyTokenOut, expectedFYTokenOut);
        assertEq(fyToken.balanceOf(bob), bobFYTokensBefore + fyTokenOut);

        // I can't sell more to the pool
        assertEq(pool.maxBaseIn(), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                NegativeInterestRatesNotAllowed.selector,
                1155000.624923905628839852e18,
                1155000.624943450946453460e18
            )
        );
        pool.sellBasePreview(10e12); // Super low value in DAI
    }

    function testUnit_tradeDAI16() public {
        console.log("buys ALL fyTokens and retrieves change");
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 bobFYTokensBefore = fyToken.balanceOf(bob);

        uint128 maxFYTokenOut = pool.maxFYTokenOut();
        assertEq(maxFYTokenOut, 122221.597288316649102088e18);
        uint128 requiredBase = pool.buyFYTokenPreview(maxFYTokenOut);

        // I'll mint what's required + an extra tenner to test the retrieve method
        asset.mint(address(pool), requiredBase + 10e18);
        uint128 baseIn = pool.buyFYToken(bob, maxFYTokenOut, type(uint128).max);

        // I should have paid the quoted amount
        assertEq(baseIn, requiredBase);
        // I should have got the max
        assertEq(fyToken.balanceOf(bob), bobFYTokensBefore + maxFYTokenOut);

        // I'll retrieve the extra 10 DAI I minted on purpose (converted into shares)
        pool.retrieveShares(bob);
        assertEq(shares.balanceOf(bob), bobSharesBefore + 9.090909090909090908e18);

        // I can't buy more from the pool
        assertEq(pool.maxFYTokenOut(), 0.000000000010502757e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                NegativeInterestRatesNotAllowed.selector,
                1155000.624933875573072429e18,
                1155000.624933934173771036e18
            )
        );
        pool.buyFYTokenPreview(3e10); // Super low value in DAI
    }
}

contract TradeDAI__WithExtraFYToken is WithExtraFYTokenDAI {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using Cast for uint256;

    function testUnit_tradeDAI07() public {
        console.log("sells base for a certain amount of FYTokens");
        uint256 aliceBeginningSharesBal = shares.balanceOf(alice);
        uint128 sharesIn = uint128(WAD);
        uint128 assetsIn = pool.unwrapPreview(sharesIn).u128();

        uint256 userFYTokenBefore = fyToken.balanceOf(bob);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Transfer shares for sale to the pool.
        asset.mint(address(pool), assetsIn);

        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            virtFYTokenBal,
            sharesIn,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(assetsIn), int256(expectedFYTokenOut));

        // Alice calls sellBase.  Confirm amounts and balances as expected.
        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(
            aliceBeginningSharesBal == shares.balanceOf(alice),
            "'From' wallet should have not increase shares tokens"
        );
        require(fyTokenOut == expectedFYTokenOut);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI08() public {
        console.log("does not sell shares beyond slippage");
        uint128 sharesIn = uint128(WAD);

        // Send 1 WAD shares to the pool.
        shares.mint(address(pool), sharesIn);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellBase.selector,
                1100213481329461717,
                340282366920938463463374607431768211455
            )
        );
        // Set min acceptable amount to uint128.max and see it revert.
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeDAI09() public {
        console.log("donating fyToken does not affect cache balances when selling base");
        uint128 baseIn = uint128(WAD);
        uint128 fyTokenDonation = uint128(WAD);

        // Donate both fyToken and shares to the pool.
        fyToken.mint(address(pool), fyTokenDonation);
        asset.mint(address(pool), baseIn);

        // Alice calls sellBase. See confirm cached balances.
        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint104 sharesCachedBefore, , , ) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Transfer shares for sale to the pool.
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
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn);

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(int256(expectedAssetsIn)), int256(int128(fyTokenOut)));

        // Alice calls buyFYToken.  Confirm caches and user balances.  Confirm sharesIn is as expected.
        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent, , ) = pool.getCache();

        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;
        uint256 sharesChange = pool.getSharesBalance() - sharesCachedCurrent;

        require(fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut, "'User2' wallet should have 1 fyToken token");

        almostEqual(sharesIn, expectedSharesIn, sharesIn / 1000000);
        require(sharesCachedCurrent + sharesChange == pool.getSharesBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_tradeDAI11() public {

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_tradeDAI12() public {
    //     console.log("donating fyToken and extra shares doesn't get absorbed into the cache when buying fyTokens");
}

// These tests ensure none of the trading functions work once the pool is matured.
contract TradeDAI__OnceMature is OnceMatureDAI {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_tradeDAI13() internal {
        console.log("doesn't allow sellBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBase(alice, 0);
    }

    function testUnit_tradeDAI14() internal {
        console.log("doesn't allow buyBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBase(alice, uint128(WAD), uint128(MAX));
    }

    function testUnit_tradeDAI15() internal {
        console.log("doesn't allow sellFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYToken(alice, 0);
    }

    function testUnit_tradeDAI16() internal {
        console.log("doesn't allow buyFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYToken(alice, uint128(WAD), uint128(MAX));
    }
}

contract TradeDAIPreviews__WithExtraFYToken is WithExtraFYTokenDAI {
    function testUnit_tradeDAI17() public {
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
    function testUnit_tradeDAI18() public {
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

    function testUnit_tradeDAI19() public {
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

    function testUnit_tradeDAI20() public {
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

contract Trade__InvariantDAI is WithMoreLiquidityDAI {
    function testUnit_tradeInvariantDAI01() public {
        console.log("buyBase, then check the invariant didn't go down");

        uint128 invariantBefore = pool.invariant();

        vm.startPrank(alice);

        for (uint256 i; i < 1000; i++) {
            uint128 expectedAssetOut = uint128(1000 * 10**asset.decimals());
            uint128 fyTokenIn = pool.buyBasePreview(expectedAssetOut);
            fyToken.transfer(address(pool), fyTokenIn);
            pool.buyBase(alice, expectedAssetOut, type(uint128).max);
        }

        // NOTE because of precision loss/rounding, the invariant goes down slightly after each trade (near zero amount)
        // so testing the invariant only goes up will fail for this specific func
        // https://www.desmos.com/calculator/8m678hqdy0
        assertApproxEqAbs(pool.invariant(), invariantBefore, 1e10);
    }

    function testUnit_tradeInvariantDAI02() public {
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

    function testUnit_tradeInvariantDAI03() public {
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

    function testUnit_tradeInvariantDAI04() public {
        console.log("sellFYToken, then check the invariant didn't go down");

        uint128 invariantBefore = pool.invariant();

        vm.startPrank(alice);

        for (uint256 i; i < 1000; i++) {
            uint128 fyTokenIn = uint128(1000 * 10**fyToken.decimals());
            fyToken.transfer(address(pool), fyTokenIn);
            pool.sellFYToken(alice, 0);
        }

        // NOTE because of precision loss/rounding, the invariant goes down slightly after each trade (near zero amount)
        // so testing the invariant only goes up will fail for this specific func
        // https://www.desmos.com/calculator/pjbd3s38zr
        assertApproxEqAbs(pool.invariant(), invariantBefore, 1e10);
    }
}
