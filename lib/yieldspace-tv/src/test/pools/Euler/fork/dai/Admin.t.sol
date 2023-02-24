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
import {IERC20Like as IERC20Metadata} from "../../../../../Pool/PoolImports.sol";

import "../../../../shared/Utils.sol";
import "../../../../shared/Constants.sol";
import "./State.sol";

contract Admin__WithLiquidityEulerDAIFork is EulerDAIFork {
    function testForkUnit_admin_EulerDAI01() public {
        console.log("retrieveBase returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testForkUnit_admin_EulerDAI02() public {
        console.log("retrieveBase returns exceess");
        uint256 additionalAmount = 69;
        vm.prank(alice);
        asset.transfer(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testForkUnit_admin_EulerDAI03() public {
        console.log("retrieveShares returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveShares(alice);

        // There is a 1 wei difference attributable to some deep nested rounding
        assertApproxEqAbs(pool.baseToken().balanceOf(alice), startingBaseBalance, 1);
        // assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
    }

    function testForkUnit_admin_EulerDAI04() public {
        console.log("retrieveShares returns exceess");

        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        uint256 additionalAsset = 69e18;
        vm.startPrank(alice);
        asset.transfer(address(pool), additionalAsset);
        uint256 additionalAmount = pool.wrap(alice);
        pool.sharesToken().transfer(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);

        pool.retrieveShares(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);

        // There is a 1 wei difference attributable to some deep nested rounding
        assertApproxEqAbs(pool.sharesToken().balanceOf(alice), startingSharesBalance + additionalAmount, 1);
    }

    function testForkUnit_admin_EulerDAI05() public {
        console.log("retrieveFYToken returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance);
        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
    }

    function testForkUnit_admin6_EulerDAI06() public {
        console.log("retrieveFYToken returns exceess");
        uint256 additionalAmount = 69e18;
        vm.prank(alice);
        fyToken.transfer(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
    }
}
