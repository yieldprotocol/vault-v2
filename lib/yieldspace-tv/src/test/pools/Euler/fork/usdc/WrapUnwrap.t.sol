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
import {IERC20Like as IERC20Metadata} from "../../../../../Pool/PoolImports.sol";

import "../../../../shared/Utils.sol";
import "../../../../shared/Constants.sol";
import "./State.sol";

contract Admin__WithLiquidityEulerUSDCFork is EulerUSDCFork {
    function testFailForkUnit_wrapUnwrap_EulerUSDC01() public {
        console.log(
            "wrap fails: shares amount is returned in asset decimals instead of correctly returning in shares decimals when the receiver is not the pool"
        );

        uint256 assetsIn = 1000 * 10**asset.decimals();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 sharesBalBefore = shares.balanceOf(alice);
        uint256 expectedSharesOut = shares.convertUnderlyingToBalance(assetsIn); // calling the shares contract "wrap" directly

        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.wrap(alice);

        uint256 sharesBalAfter = shares.balanceOf(alice);
        uint256 assetBalAfter = asset.balanceOf(alice);
        assertEq(assetBalAfter - assetBalBefore, assetsIn);
        assertApproxEqAbs(sharesBalAfter, expectedSharesOut, 10); // NOTE account for any one wei issue discrepancies
    }
}
