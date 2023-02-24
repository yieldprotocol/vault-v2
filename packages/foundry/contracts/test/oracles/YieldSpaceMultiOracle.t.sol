// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { IPool } from "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import { IPoolOracle } from "@yield-protocol/yieldspace-tv/src/interfaces/IPoolOracle.sol";
import { YieldSpaceMultiOracle } from "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { Mocks } from "../utils/Mocks.sol";
import { TestConstants } from "../utils/TestConstants.sol";

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

    // Harness vars
    bytes6 public base;
    bytes6 public quote;
    uint128 public unitForBase;
    uint128 public unitForQuote;

    modifier onlyMock() {
        if (vm.envOr(MOCK, true))
        _;
    }

    modifier onlyHarness() {
        if (vm.envOr(MOCK, true)) return;
        _;
    }

    function setUpMock() public onlyMock {
        vm.warp(NOW);

        pool = IPool(Mocks.mock("Pool"));
        pOracle = IPoolOracle(Mocks.mock("IPoolOracle"));

        oracle = new YieldSpaceMultiOracle(pOracle);

        oracle.grantRole(oracle.setSource.selector, address(0xa11ce));

        pOracle.updatePool.mock(pool);

        vm.prank(address(0xa11ce));
        oracle.setSource(FYUSDC2206, USDC, pool);
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        oracle = YieldSpaceMultiOracle(vm.envAddress("ORACLE"));

        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        unitForBase = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForQuote = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }


    function testSourceHasAuth() public onlyMock {
        vm.expectRevert("Access denied");
        vm.prank(address(0xb0b));
        oracle.setSource(FYUSDC2206, USDC, pool);
    }

    function testSetSource() public onlyMock {
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

    function testRevertOnUnknownPair() public onlyMock {
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

    function testPeekSameBaseAsset() public onlyMock {
        (uint256 value, uint256 updateTime) = oracle.peek(
            FYUSDC2206,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testPeekSameQuoteAsset() public onlyMock {
        (uint256 value, uint256 updateTime) = oracle.peek(USDC, USDC, 1000e6);

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testPeekDiscountLendingPosition() public onlyMock {
        pOracle.peekSellBasePreview.mock(pool, 1000e6, 1003.171118e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.peek(
            USDC,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1003.171118e6);
    }

    function testPeekDiscountBorrowingPosition() public onlyMock {
        pOracle.peekSellFYTokenPreview.mock(pool, 1000e6, 996.313029e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.peek(
            FYUSDC2206,
            USDC,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 996.313029e6);
    }

    function testGetSameBaseAsset() public onlyMock {
        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2206,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testGetSameQuoteAsset() public onlyMock {
        (uint256 value, uint256 updateTime) = oracle.get(USDC, USDC, 1000e6);

        assertEq(updateTime, NOW);
        assertEq(value, 1000e6);
    }

    function testGetDiscountLendingPosition() public onlyMock {
        pOracle.getSellBasePreview.mock(pool, 1000e6, 1003.171118e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.get(
            USDC,
            FYUSDC2206,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 1003.171118e6);
    }

    function testGetDiscountBorrowingPosition() public onlyMock {
        pOracle.getSellFYTokenPreview.mock(pool, 1000e6, 996.313029e6, NOW);

        (uint256 value, uint256 updateTime) = oracle.get(
            FYUSDC2206,
            USDC,
            1000e6
        );

        assertEq(updateTime, NOW);
        assertEq(value, 996.313029e6);
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        (amount, updateTime) = oracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        assertApproxEqRel(amount, unitForQuote, unitForQuote / 100);
        // and reverse
        (amount, updateTime) = oracle.peek(quote, base, unitForQuote);
        assertApproxEqRel(amount, unitForBase, unitForBase / 100);
    }
}
