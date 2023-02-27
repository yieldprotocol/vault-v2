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
import {ZeroState, ZeroStateParams} from "../../shared/ZeroState.sol";

import "../../../Pool/PoolErrors.sol";
import {Exp64x64} from "../../../Exp64x64.sol";
import {Math64x64} from "../../../Math64x64.sol";
import {YieldMath} from "../../../YieldMath.sol";
import {Cast} from  "@yield-protocol/utils-v2/src/utils/Cast.sol";

// DAI states
abstract contract ZeroStateDai is ZeroState {
    constructor() ZeroState(ZeroStateParams("DAI", "DAI", 18, "4626", false)) {}
}

abstract contract PoolInitialized is ZeroStateDai {
    function setUp() public virtual override {
        super.setUp();

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));

        // Alice calls init.
        vm.prank(alice);
        pool.init(alice);

        // elapse some time after initialization
        vm.warp(block.timestamp + 60);

        // Update the price of shares to value of state variables: cNumerator/cDenominator
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(shares.decimals())) / 9;
    }
}

abstract contract WithLiquidityDAI is ZeroStateDai {
    function setUp() public virtual override {
        super.setUp();

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));

        // Alice calls init.
        vm.prank(alice);
        pool.init(alice);

        // elapse some time after initialization
        vm.warp(block.timestamp + 60);

        // Update the price of shares to value of state variables: cNumerator/cDenominator
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(shares.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);

        // elapse some time after initialization
        vm.warp(block.timestamp + 60);
    }
}

abstract contract WithExtraFYTokenDAI is WithLiquidityDAI {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public virtual override {
        super.setUp();

        // Donate an additional 30 WAD fyToken to pool.
        uint256 additionalFYToken = 30 * WAD;
        fyToken.mint(address(pool), additionalFYToken);

        // Alice calls sellFYToken
        vm.prank(alice);
        pool.sellFYToken(address(this), 0);
    }
}

abstract contract OnceMatureDAI is WithExtraFYTokenDAI {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public override {
        super.setUp();
        // Fast forward block timestamp to maturity date.
        vm.warp(pool.maturity());
    }
}

// USDC states
abstract contract ZeroStateUSDC is ZeroState {
    constructor() ZeroState(ZeroStateParams("USDC", "USDC", 6, "4626", false)) {}
}

abstract contract WithLiquidityUSDC is ZeroStateUSDC {
    function setUp() public virtual override {
        super.setUp();

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));

        // Alice calls init.
        vm.prank(alice);
        pool.init(alice);

        // Update the price of shares to value of state variables: cNumerator/cDenominator
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(shares.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);
    }
}

abstract contract WithExtraFYTokenUSDC is WithLiquidityUSDC {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * 1e6;
        fyToken.mint(address(pool), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(alice, 0);
    }
}

abstract contract OnceMatureUSDC is WithExtraFYTokenUSDC {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public override {
        super.setUp();
        // Fast forward block timestamp to maturity date.
        vm.warp(pool.maturity());
    }
}

abstract contract WithMoreLiquidityUSDC is WithExtraFYTokenUSDC {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(alice);

        uint256 fyTokenIn = 1_000_000 * 10**fyToken.decimals();
        uint256 assetIn = 10_000_000 * 10**asset.decimals();
        fyToken.transfer(address(pool), fyTokenIn);
        asset.transfer(address(pool), assetIn);
        pool.mint(alice, alice, 0, MAX);

        vm.stopPrank();
    }
}

abstract contract WithMoreLiquidityDAI is WithExtraFYTokenDAI {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(alice);

        uint256 fyTokenIn = 1_000_000 * 10**fyToken.decimals();
        uint256 assetIn = 10_000_000 * 10**asset.decimals();
        fyToken.transfer(address(pool), fyTokenIn);
        asset.transfer(address(pool), assetIn);
        pool.mint(alice, alice, 0, MAX);

        vm.stopPrank();
    }
}
