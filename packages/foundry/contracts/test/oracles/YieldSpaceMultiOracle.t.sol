// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../utils/Mocks.sol";
import "../utils/TestConstants.sol";
import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";

contract YieldSpaceMultiOracleTest is Test, TestConstants {
    using Mocks for *;
    using Math64x64 for int128;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed pool,
        uint32 maturity,
        int128 ts,
        int128 g
    );

    uint256 internal constant NOW = 1645870528;
    uint256 internal constant TWAR = 1073988998320842609;
    uint32 internal constant MATURITY = 1656039600;
    int128 internal constant TS = 23381681843;
    int128 internal constant G1 = 13835058055282163712;
    int128 internal constant G2 = 24595658764946068821;

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
        emit SourceSet(FYUSDC2206, USDC, pool, MATURITY, TS, G2);

        vm.expectEmit(true, true, true, true);
        emit SourceSet(USDC, FYUSDC2206, pool, MATURITY, TS, G1);

        pOracle.update.verify(pool);

        vm.prank(address(0xa11ce));
        oracle.setSource(FYUSDC2206, USDC, pool);

        (address _pool, uint32 _maturity, bool _inverse, int128 gts) = oracle
            .sources(FYUSDC2206, USDC);
        assertEq(_pool, pool);
        assertEq(_maturity, MATURITY);
        assertEq(_inverse, false);
        assertEq(gts, TS.mul(G2));

        (_pool, _maturity, _inverse, gts) = oracle.sources(USDC, FYUSDC2206);
        assertEq(_pool, pool);
        assertEq(_maturity, MATURITY);
        assertEq(_inverse, true);
        assertEq(gts, TS.mul(G1));
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

    function testPeekDiscountBorrowingPosition() public {
        pOracle.peek.mock(pool, TWAR);

        (uint256 value, uint256 updateTime) = oracle.peek(
            FYUSDC2206,
            USDC,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 998.774016e6);
    }

    function testPeekSameAsset() public {
        (uint256 value, uint256 updateTime) = oracle.peek(
            FYUSDC2206,
            FYUSDC2206,
            1000e6
        );

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
        assertEq(value, 1000.690277e6);
    }

    function testGetDiscountBorrowingPosition() public {
        pOracle.get.mock(pool, TWAR);

        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2206,
            USDC,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 998.774016e6);
    }

    function testGetSameAsset() public {
        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2206,
            FYUSDC2206,
            1000e6
        );

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
        assertEq(value, 1000.690277e6);
    }
}
