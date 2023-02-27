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

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import "./pools/4626/State.sol";

import "../Pool/PoolErrors.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";

contract TWAR__ZeroState is ZeroStateDai {
    function testUnit_twar1() public {
        console.log("twar values updated and returned correctly after initial mint");
        assertEq(pool.cumulativeRatioLast(), 0);

        // initialize pool, add initial liquidity and set new price on shares
        shares.mint(address(pool), INITIAL_YVDAI);
        vm.prank(alice);
        pool.init(bob);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);

        // since cumRatLast is on a lag, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);
        // since no time has lapsed, currentCumRat should also be zero.
        (uint256 currCumRat1, uint256 btimestamp1) = pool.currentCumulativeRatio();
        assertEq(currCumRat1, 0);
        assertEq(btimestamp1, block.timestamp);

        // advance time 60 seconds
        uint256 timewarp = 60;
        vm.warp(block.timestamp + timewarp);

        // since cumRatLast is on a lag and no updates to reserves have been made, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);

        // since time has lapsed, currentCumRat should be increased
        (uint104 sharesReserves, uint104 fyTokenReserves, , ) = pool.getCache();
        uint256 expectedCurrCumRat = pool.cumulativeRatioLast() +
            pool.calcRatioSeconds(fyTokenReserves, sharesReserves, timewarp);
        (uint256 currCumRat2, uint256 btimestamp2) = pool.currentCumulativeRatio();
        assertEq(currCumRat2, expectedCurrCumRat);
        assertEq(btimestamp2, btimestamp1 + timewarp);
    }
}

contract TWAR__PoolInitialized is PoolInitialized {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_twar2() public {
        console.log("twar values updated and returned correctly after additional mint");
        // since cumRatLast is on a lag, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);

        // Send some shares to the pool.
        uint256 sharesToMint = 10e18;
        shares.mint(address(pool), sharesToMint);

        // Alice calls mint to Bob.
        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        // fast forward time
        uint256 timewarp = 100;
        vm.warp(block.timestamp + timewarp);

        (uint104 sharesReserves, uint104 fyTokenReserves, , ) = pool.getCache();

        // expect the total ratio seconds to be 60 (ray) based on the 1:1 ratio established
        // in setup and the 60 seconds that had elapsed after
        assertEq(pool.cumulativeRatioLast(), 60 * 1e27);
        // expect currCumRat to have increased
        (uint256 currCumRat1, ) = pool.currentCumulativeRatio();
        uint256 expectedCurrCumRat = pool.cumulativeRatioLast() +
            pool.calcRatioSeconds(fyTokenReserves, sharesReserves, timewarp);
        assertEq(currCumRat1, expectedCurrCumRat);
    }

    function testUnit_twar3() public {
        console.log("twar values updated and returned correctly a buy of base tokens");

        // since cumRatLast is on a lag, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);

        // Send FYToken, sync, and calc expected FYTokenIn
        fyToken.mint(address(pool), 5e18);
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        uint128 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            virtFYTokenBal,
            3e18,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );

        // Send some fyToken to the pool.
        fyToken.mint(address(pool), expectedFYTokenIn); // send an extra wad of shares

        // Alice buys base
        vm.startPrank(alice);
        pool.buyBase(alice, 3e18, type(uint128).max);

        // fast forward time
        uint256 timewarp = 100;
        vm.warp(block.timestamp + timewarp);

        // expect the total ratio seconds to be 60 (ray) based on the 1:1 ratio established
        // in setup and the 60 seconds that had elapsed after
        assertEq(pool.cumulativeRatioLast(), 60 * 1e27);

        // expect currCumRat to have increased
        (uint256 currCumRat1, ) = pool.currentCumulativeRatio();
        (uint104 sharesReserves_, uint104 fyTokenReserves, , ) = pool.getCache();
        uint256 expectedCurrCumRat = pool.cumulativeRatioLast() +
            pool.calcRatioSeconds(fyTokenReserves, sharesReserves_, timewarp);
        assertEq(currCumRat1, expectedCurrCumRat);

        vm.warp(block.timestamp + 1000);
        expectedCurrCumRat += pool.calcRatioSeconds(fyTokenReserves, sharesReserves_, 1000);
        (uint256 currCumRat2, ) = pool.currentCumulativeRatio();
        assertEq(expectedCurrCumRat + 1, currCumRat2); // off by one wei
    }

    function testUnit_twar4() public {
        console.log("twar values updated and returned correctly a sell of shares tokens");

        // since cumRatLast is on a lag, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);

        // skew the pool to represent some trades
        (, uint104 sharesReserves0, uint104 fyTokenReserves0, ) = pool.getCache();

        fyToken.mint(address(pool), 2_000_000 * 1e18);
        pool.sync();

        // sellBase
        shares.mint(address(pool), 1e18);
        vm.startPrank(alice);
        pool.sellBase(alice, 0);

        // fast forward time
        uint256 timewarp = 100;
        vm.warp(block.timestamp + timewarp);

        // expect the total ratio seconds to be 60 (ray) based on the 1:1 ratio established
        assertEq(pool.cumulativeRatioLast(), 60 * 1e27);

        // expect currCumRat to have increased
        (uint256 currCumRat1, ) = pool.currentCumulativeRatio();
        (uint104 sharesReserves, uint104 fyTokenReserves, , ) = pool.getCache();
        uint256 expectedCurrCumRat = pool.cumulativeRatioLast() +
            pool.calcRatioSeconds(fyTokenReserves, sharesReserves, timewarp);
        assertEq(currCumRat1, expectedCurrCumRat);

        vm.warp(block.timestamp + 1000);
        expectedCurrCumRat += pool.calcRatioSeconds(fyTokenReserves, sharesReserves, 1000);
        (uint256 currCumRat2, ) = pool.currentCumulativeRatio();
        assertApproxEqAbs(currCumRat2, expectedCurrCumRat, 1);
    }

    function testUnit_twar5() public {
        console.log("twar values updated and returned correctly a sell of FYtokens");

        // since cumRatLast is on a lag, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);

        // Send some shares to the pool.
        fyToken.mint(address(pool), 10e18); // send an extra wad of shares

        // calc expected FYTokenIn
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        uint128 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            virtFYTokenBal,
            3e18,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );

        // Alice calls mint to Bob.
        vm.startPrank(alice);
        pool.sellFYToken(alice, expectedSharesOut);

        // fast forward time
        uint256 timewarp = 100;
        vm.warp(block.timestamp + timewarp);

        // expect the total ratio seconds to be 60 (ray) based on the 1:1 ratio established
        // in setup and the 60 seconds that had elapsed after
        assertEq(pool.cumulativeRatioLast(), 60 * 1e27);

        // expect currCumRat to have increased
        (uint256 currCumRat1, ) = pool.currentCumulativeRatio();
        (uint104 sharesReserves_, uint104 fyTokenReserves, , ) = pool.getCache();
        uint256 expectedCurrCumRat = pool.cumulativeRatioLast() +
            pool.calcRatioSeconds(fyTokenReserves, sharesReserves_, timewarp);
        assertEq(currCumRat1, expectedCurrCumRat);

        vm.warp(block.timestamp + 1000);
        expectedCurrCumRat += pool.calcRatioSeconds(fyTokenReserves, sharesReserves_, 1000);
        (uint256 currCumRat2, ) = pool.currentCumulativeRatio();
        assertApproxEqAbs(currCumRat2, expectedCurrCumRat, 1);
    }

    function testUnit_twar6() public {
        console.log("twar values updated and returned correctly a buy of FYtokens");

        // since cumRatLast is on a lag, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);

        // skew the pool to represent some trades
        (, uint104 sharesReserves0, uint104 fyTokenReserves0, ) = pool.getCache();

        fyToken.mint(address(pool), 2_000_000 * 1e18);
        pool.sync();

        // send over shares and buy fytoken
        shares.mint(address(pool), 5e18);
        vm.prank(alice);
        pool.buyFYToken(alice, 3e18, type(uint128).max);

        // fast forward time
        uint256 timewarp = 100;
        vm.warp(block.timestamp + timewarp);

        // expect the total ratio seconds to be 60 (ray) based on the 1:1 ratio established
        // in setup and the 60 seconds that had elapsed after
        assertEq(pool.cumulativeRatioLast(), 60 * 1e27);

        // expect currCumRat to have increased
        (uint256 currCumRat1, ) = pool.currentCumulativeRatio();
        (uint104 sharesReserves, uint104 fyTokenReserves, , ) = pool.getCache();
        uint256 expectedCurrCumRat = pool.cumulativeRatioLast() +
            pool.calcRatioSeconds(fyTokenReserves, sharesReserves, timewarp);
        assertEq(currCumRat1, expectedCurrCumRat);

        vm.warp(block.timestamp + 1000);
        expectedCurrCumRat += pool.calcRatioSeconds(fyTokenReserves, sharesReserves, 1000);
        (uint256 currCumRat2, ) = pool.currentCumulativeRatio();
        assertEq(currCumRat2, expectedCurrCumRat);
    }

    function testUnit_twar7() public {
        console.log("twar values updated and returned correctly a burn of lp tokens");

        // since cumRatLast is on a lag, it should still be zero.
        assertEq(pool.cumulativeRatioLast(), 0);

        // Send some shares to the pool.
        shares.mint(address(pool), 10e18); // send an extra wad of shares

        // Alice calls mint to Bob.
        vm.startPrank(alice);
        pool.mint(address(pool), address(pool), 0, MAX);
        uint256 toBurn = pool.balanceOf(address(pool));
        pool.burn(alice, alice, 0, type(uint128).max);

        // fast forward time
        uint256 timewarp = 100;
        vm.warp(block.timestamp + timewarp);

        // expect the total ratio seconds to be 60 (ray) based on the 1:1 ratio established
        // in setup and the 60 seconds that had elapsed after
        assertEq(pool.cumulativeRatioLast(), 60 * 1e27);

        // expect currCumRat to have increased
        (uint256 currCumRat1, ) = pool.currentCumulativeRatio();
        (uint104 sharesReserves, uint104 fyTokenReserves, , ) = pool.getCache();
        uint256 expectedCurrCumRat = pool.cumulativeRatioLast() +
            pool.calcRatioSeconds(fyTokenReserves, sharesReserves, timewarp);
        assertEq(currCumRat1, expectedCurrCumRat);

        vm.warp(block.timestamp + 1000);
        expectedCurrCumRat += pool.calcRatioSeconds(fyTokenReserves, sharesReserves, 1000);
        (uint256 currCumRat2, ) = pool.currentCumulativeRatio();
        assertApproxEqAbs(currCumRat2, expectedCurrCumRat, 1);
    }
}
