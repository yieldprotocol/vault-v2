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
//    These tests are exactly copy and pasted from the MintBurn.t.sol and TradingUSDC.t.sol test suites.
//    The only difference is they are setup on the PoolEuler contract instead of the Pool contract
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../Pool/PoolErrors.sol";
import {Exp64x64} from "../../../../Exp64x64.sol";
import {Math64x64} from "../../../../Math64x64.sol";
import {YieldMath} from "../../../../YieldMath.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";

import "../../../shared/Utils.sol";
import "../../../shared/Constants.sol";
import {ZeroState, ZeroStateParams} from "../../../shared/ZeroState.sol";

abstract contract ZeroStateEulerUSDC is ZeroState {
    using Cast for uint256;

    constructor() ZeroState(ZeroStateParams("USDC", "USDC", 6, "EulerVault", false)) {}

    //TODO: not sure where to put this fn
    // Euler eTokens always use 18 decimals so using this fn changes decimals to that of the base token,
    // for example eUSDC is converted from fp18 to fp6.
    function getSharesBalanceWithDecimalsAdjusted(address who) public returns (uint128) {
        return (shares.balanceOf(who) / pool.scaleFactor()).u128();
    }
}

abstract contract WithLiquidityEulerUSDC is ZeroStateEulerUSDC {
    function setUp() public virtual override {
        super.setUp();

        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));
        vm.prank(alice);
        pool.init(alice);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(asset.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);

        // There is a fractional amount of excess eUSDC shares in the pool.
        // as a result of the decimals mismatch between eUSDC (18) and actual USDC (6).
        // The amount is less than 2/10 of a wei of USDC: 0.000000181818181819 USDC
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();
        uint256 fractionalExcess = pool.sharesToken().balanceOf(address(pool)) - startingSharesCached * 1e12;
        assertEq(fractionalExcess, 181818181819);
        pool.retrieveShares(address(0x0)); // clear that fractional excess out for cleaner tests below
    }
}

abstract contract WithExtraFYTokenEulerUSDC is WithLiquidityEulerUSDC {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * 1e6;
        fyToken.mint(address(pool), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(alice), 0);
    }
}

abstract contract OnceMatureUSDC is WithExtraFYTokenEulerUSDC {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public override {
        super.setUp();
        vm.warp(pool.maturity());
    }
}
