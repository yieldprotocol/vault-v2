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

abstract contract EulerUSDCFork is ForkTestCore {
    uint8 decimals;
    uint256 ONE_SCALED; // scaled to asset decimals

    function fundAddr(address addr) public {
        deal(address(asset), addr, (ONE_SCALED * 100_000));

        vm.prank(ladle);
        fyToken.mint(addr, (ONE_SCALED * 100_000)); // scale for usdc decimals
    }

    function setUp() public virtual {
        pool = Pool(MAINNET_USDC_JUNE_2023_POOL);
        asset = ERC20(address(pool.baseToken()));
        fyToken = FYToken(address(pool.fyToken()));
        shares = IEToken(address(pool.sharesToken()));
        ONE_SCALED = 1 * 10**(asset.decimals());

        fundAddr(alice);
    }
}

abstract contract EulerUSDCForkWithLiquidity is EulerUSDCFork {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(alice);

        // try to mint pool tokens
        asset.transfer(address(pool), (ONE_SCALED * 5000)); // scale for usdc decimals
        fyToken.transfer(address(pool), (ONE_SCALED * 5000) / 2); // scale for usdc decimals
        pool.mint(alice, alice, 0, MAX);
        pool.retrieveBase(alice);
        pool.retrieveFYToken(alice);
        pool.retrieveShares(alice);

        vm.stopPrank();
    }
}

// skews the reserves to have more real fyToken
abstract contract EulerUSDCForkSkewedReserves is EulerUSDCForkWithLiquidity {
    function setUp() public virtual override {
        super.setUp();

        // skew the pool toward more fyToken reserves by buying base; currently there are 0 real fyToken reserves
        // sell fyToken for base
        vm.startPrank(alice);
        fyToken.transfer(address(pool), 20000 * 10**fyToken.decimals());
        pool.sellFYToken(address(alice), 0);

        vm.stopPrank();
    }
}
