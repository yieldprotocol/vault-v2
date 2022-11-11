// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../utils/Mocks.sol";
import "../utils/TestConstants.sol";
import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";

contract YieldSpaceMultiOracleTest is Test, TestConstants {
    using Mocks for *;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        IPool indexed pool
    );

    uint256 internal NOW = 1645870528;

    IPoolOracle internal pOracle;
    IPool internal pool;

    YieldSpaceMultiOracle internal oracle;

    function setUp() public {
        vm.warp(NOW);

        pool = IPool(Mocks.mock("Pool"));
        pOracle = IPoolOracle(Mocks.mock("IPoolOracle"));

        oracle = new YieldSpaceMultiOracle(pOracle);

        oracle.grantRole(oracle.setSource.selector, address(0xa11ce));

        pOracle.updatePool.mock(pool);

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
        emit SourceSet(FYUSDC2206, USDC, pool);

        vm.expectEmit(true, true, true, true);
        emit SourceSet(USDC, FYUSDC2206, pool);

        pOracle.updatePool.verify(pool);

        vm.prank(address(0xa11ce));
        oracle.setSource(FYUSDC2206, USDC, pool);

        (IPool _pool, bool _lending) = oracle.sources(FYUSDC2206, USDC);
        assertEq(address(_pool), address(pool));
        assertEq(_lending, false);

        (_pool, _lending) = oracle.sources(USDC, FYUSDC2206);
        assertEq(address(_pool), address(pool));
        assertEq(_lending, true);
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
        pOracle.peekSellBasePreview.mock(pool, 1000e6, 1003.171118e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.peek(
            USDC,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1003.171118e6);
    }

    function testPeekDiscountBorrowingPosition() public {
        pOracle.peekSellFYTokenPreview.mock(pool, 1000e6, 996.313029e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.peek(
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
        pOracle.getSellBasePreview.mock(pool, 1000e6, 1003.171118e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.get(
            USDC,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1003.171118e6);
    }

    function testGetDiscountBorrowingPosition() public {
        pOracle.getSellFYTokenPreview.mock(pool, 1000e6, 996.313029e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2206,
            USDC,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 996.313029e6);
    }
}
