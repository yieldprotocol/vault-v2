// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../utils/Mocks.sol";
import "../utils/TestConstants.sol";
import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";

contract YieldSpaceMultiOracleTest is Test, TestConstants {
    using Mocks for *;
    using Math64x64 for *;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed pool,
        uint32 maturity,
        int128 ts,
        int128 mu
    );

    uint256 internal Z = 1_100_000e6;
    uint256 internal Y = 1_500_000e6;
    uint256 internal TWAR = Y.divu(Z).mulu(1e18);
    uint256 internal NOW = 1645870528;
    uint32 internal MATURITY = uint32(NOW + (90 * 24 * 60 * 60 * 10));
    int128 internal TS = uint256(1).divu(25 * 365 * 24 * 60 * 60 * 10);
    int128 internal G1 = uint256(900).divu(1000);
    int128 internal G2 = uint256(1050).divu(1000);
    int128 internal C = uint256(11).divu(10);
    int128 internal MU = uint256(105).divu(100);

    IPoolOracle internal pOracle;
    address internal pool;

    YieldSpaceMultiOracle internal oracle;

    function setUp() public {
        vm.warp(NOW);

        pool = Mocks.mock("Pool");
        pOracle = IPoolOracle(Mocks.mock("IPoolOracle"));

        oracle = new YieldSpaceMultiOracle(pOracle);

        IPool(pool).maturity.mock(MATURITY);
        IPool(pool).ts.mock(TS);
        IPool(pool).g1.mock(G1);
        IPool(pool).g2.mock(G2);
        IPool(pool).getC.mock(C);
        IPool(pool).mu.mock(MU);

        oracle.grantRole(oracle.setSource.selector, address(0xa11ce));

        pOracle.update.mock(pool);

        vm.prank(address(0xa11ce));
        oracle.setSource(FYUSDC2206, USDC, pool);
    }

    function testSourceHasAuth() public {
        vm.expectRevert("Access denied");
        vm.prank(address(0xb0b));
        oracle.setSource(FYUSDC2206, USDC, pool);
    }

    function testSetSource() public {
        vm.expectEmit(true, true, true, true);
        emit SourceSet(FYUSDC2206, USDC, pool, MATURITY, TS, MU);

        vm.expectEmit(true, true, true, true);
        emit SourceSet(USDC, FYUSDC2206, pool, MATURITY, TS, MU);

        pOracle.update.verify(pool);

        vm.prank(address(0xa11ce));
        oracle.setSource(FYUSDC2206, USDC, pool);

        (
            address _pool,
            uint32 _maturity,
            bool _inverse,
            int128 ts,
            int128 mu
        ) = oracle.sources(FYUSDC2206, USDC);
        assertEq(_pool, pool);
        assertEq(_maturity, MATURITY);
        assertEq(_inverse, false);
        assertEq(ts, TS);
        assertEq(mu, MU);

        (_pool, _maturity, _inverse, ts, mu) = oracle.sources(USDC, FYUSDC2206);
        assertEq(_pool, pool);
        assertEq(_maturity, MATURITY);
        assertEq(_inverse, true);
        assertEq(ts, TS);
        assertEq(mu, MU);
    }

    function testRevertOnUnknownPair() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldSpaceMultiOracle.SourceNotFound.selector,
                FYETH2206,
                USDC
            )
        );
        oracle.peek(FYETH2206, USDC, 2 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldSpaceMultiOracle.SourceNotFound.selector,
                FYETH2206,
                USDC
            )
        );
        oracle.get(FYETH2206, USDC, 2 ether);
    }

    function testPeekFYTokenToBase() public {
        pOracle.peek.mock(pool, TWAR);

        (uint256 value, uint256 updateTime) = oracle.peek(
            FYUSDC2206,
            USDC,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 996.313029e6);
    }

    function testPeekSameBaseAsset() public {
        (uint256 value, uint256 updateTime) = oracle.peek(
            FYUSDC2206,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testPeekSameQuoteAsset() public {
        (uint256 value, uint256 updateTime) = oracle.peek(USDC, USDC, 1000e6);

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testPeekDiscountLendingPosition() public {
        pOracle.peek.mock(pool, TWAR);

        (uint256 value, uint256 updateTime) = oracle.peek(
            USDC,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1003.171118e6);
    }

    function testGetDiscountBorrowingPosition() public {
        pOracle.get.mock(pool, TWAR);

        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2206,
            USDC,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 996.313029e6);
    }

    function testGetSameBaseAsset() public {
        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2206,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testGetSameQuoteAsset() public {
        (uint256 value, uint256 updateTime) = oracle.get(USDC, USDC, 1000e6);

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testGetDiscountLendingPosition() public {
        pOracle.get.mock(pool, TWAR);

        (uint256 value, uint256 updateTime) = oracle.get(
            USDC,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1003.171118e6);
    }
}
