// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { AccessControl } from "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import { StrategyOracle } from "../../oracles/strategy/StrategyOracle.sol";
import { IStrategy } from "../../interfaces/IStrategy.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { TestExtensions } from "../utils/TestExtensions.sol";

contract StrategyOracleTest is Test, TestConstants, TestExtensions {
    StrategyOracle public strategyOracle;
    bytes6 baseId = 0xc02aaa39b223;
    bytes6 quoteId; // = 0x1f9840a85d5a;

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

    function setUpMock() public {
        vm.createSelectFork(MAINNET, 15917726);

        strategyOracle = new StrategyOracle();
        strategyOracle.grantRole(
            strategyOracle.setSource.selector,
            address(this)
        );
        quoteId = IStrategy(0x831dF23f7278575BA0b136296a285600cD75d076).baseId();
        strategyOracle.setSource(
            baseId,
            IStrategy(0x831dF23f7278575BA0b136296a285600cD75d076)
        );
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        strategyOracle = StrategyOracle(vm.envAddress("ORACLE"));

        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        unitForBase = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForQuote = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testPeek() public onlyMock {
        (uint256 amount, ) = strategyOracle.peek(
            bytes32(baseId),
            bytes32(quoteId),
            1e18
        );
        assertEq(amount, 1000626265483608379);
    }

    function testPeekReversed() public onlyMock {
        (uint256 amount, ) = strategyOracle.peek(
            bytes32(quoteId),
            bytes32(baseId),
            1e18
        );
        assertEq(amount, 999374126479374692);
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        (amount, updateTime) = strategyOracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        assertApproxEqRel(amount, 1e18, 1e18);
        // and reverse
        (amount, updateTime) = strategyOracle.peek(quote, base, unitForQuote);
        assertApproxEqRel(amount, 1e18, 1e18);
    }
}
