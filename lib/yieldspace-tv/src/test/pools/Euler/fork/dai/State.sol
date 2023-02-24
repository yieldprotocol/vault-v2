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
//    State for mainnet fork test environment
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../../Pool/PoolErrors.sol";
import {Exp64x64} from "../../../../../Exp64x64.sol";
import {Math64x64} from "../../../../../Math64x64.sol";
import {YieldMath} from "../../../../../YieldMath.sol";
import {Pool} from "../../../../../Pool/Pool.sol";
import {ERC20, AccessControl} from "../../../../../Pool/PoolImports.sol";
// Using FYTokenMock.sol here for the interface so we don't need to add a new dependency
// to this repo just to get an interface:
import {FYTokenMock as FYToken} from "../../../../mocks/FYTokenMock.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";
import {IEToken} from "../../../../../interfaces/IEToken.sol";

import "../../../../shared/Utils.sol";
import "../../../../shared/Constants.sol";
import {ForkTestCore} from "../../../../shared/ForkTestCore.sol";

abstract contract EulerDAIFork is ForkTestCore {
    IEToken eToken;

    function fundAddr(address addr) public {
        deal(address(asset), addr, WAD * 100_000);

        vm.prank(ladle);
        fyToken.mint(addr, WAD * 100_000);
    }

    function setUp() public virtual {
        pool = Pool(MAINNET_DAI_JUNE_2023_POOL);
        asset = ERC20(address(pool.baseToken()));
        fyToken = FYToken(address(pool.fyToken()));
        eToken = IEToken(address(pool.sharesToken()));

        fundAddr(alice);
    }
}

abstract contract EulerDAIForkWithLiquidity is EulerDAIFork {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(alice);

        // try to mint pool tokens
        asset.transfer(address(pool), WAD * 5000);
        fyToken.transfer(address(pool), (WAD * 5000) / 2);
        pool.mint(alice, alice, 0, MAX);

        vm.stopPrank();
    }
}
