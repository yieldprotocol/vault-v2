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
import {ERC4626TokenMock} from "./mocks/ERC4626TokenMock.sol";
import {ZeroState, ZeroStateParams} from "./shared/ZeroState.sol";
import {IERC20Like} from "../interfaces/IERC20Like.sol";

import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";

abstract contract WithLiquidity is ZeroState {
    constructor() ZeroState(ZeroStateParams("DAI", "DAI", 18, "4626", false)) {}

    function setUp() public virtual override {
        super.setUp();
        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));

        vm.prank(alice);
        pool.init(alice);

        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(shares.decimals())) / 9;

        pool.sellFYToken(alice, 0);
    }
}

contract Admin__WithLiquidity is WithLiquidity {
    function testUnit_admin1() public {
        console.log("balance management getters return correct values");
        require(pool.getSharesBalance() == shares.balanceOf(address(pool)));
        require(pool.getBaseBalance() > pool.getSharesBalance());
        require(
            pool.getCurrentSharePrice() == ERC4626TokenMock(address(shares)).convertToAssets(10**shares.decimals())
        );
        require(pool.getFYTokenBalance() == fyToken.balanceOf(address(pool)) + pool.totalSupply());
        (uint104 sharesCached, uint104 fyTokenCached, uint32 blockTimeStampLast, uint16 g1fee_) = pool.getCache();
        require(g1fee_ == g1Fee);
        almostEqual(sharesCached, 1100000000000000000000000, 100000000);
        require(fyTokenCached == 1154999999999999999952295);
        require(blockTimeStampLast == block.timestamp);
        uint256 expectedCurrentCumulativeRatio = pool.cumulativeRatioLast() +
            ((uint256(fyTokenCached) * 1e27) * (block.timestamp - blockTimeStampLast)) /
            sharesCached;
        (uint256 actualCurrentCumulativeRatio, ) = pool.currentCumulativeRatio();
        require(actualCurrentCumulativeRatio == expectedCurrentCumulativeRatio);
        shares.mint(address(pool), 1e18);
        pool.sync();
        (uint104 sharesCachedNew, , , ) = pool.getCache();
        almostEqual(sharesCachedNew, sharesCached + 1e18, 100000000);
    }

    function testUnit_admin2() public {
        console.log("setFees cannot be set without auth");
        (, , , uint fee) = pool.getCache();
        assertEq(fee, 9500);
        vm.expectRevert(bytes("Access denied"));
        pool.setFees(9600);
        (, , , fee) = pool.getCache();
        assertEq(fee, 9500);

        vm.prank(bob);
        pool.setFees(9600);
        (, , , fee) = pool.getCache();
        assertEq(fee, 9600);
    }

    function testUnit_admin3() public {
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

    function testUnit_admin4() public {
        console.log("retrieveBase returns exceess");
        uint256 additionalAmount = 69;
        IERC20Like base = IERC20Like(address(pool.baseToken()));
        vm.prank(alice);
        base.transfer(address(pool), additionalAmount);

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

    function testUnit_admin5() public {
        console.log("retrieveShares returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveShares(alice);

        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
    }

    function testUnit_admin6() public {
        console.log("retrieveShares returns exceess");
        uint256 additionalAmount = 69e18;
        shares.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveShares(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance + additionalAmount);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
    }

    function testUnit_admin7() public {
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

    function testUnit_admin8() public {
        console.log("retrieveFYToken returns exceess");
        uint256 additionalAmount = 69e18;
        fyToken.mint(address(pool), additionalAmount);

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
