// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import { AccessControl } from "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import { CrabOracle } from "../../oracles/crab/CrabOracle.sol";
import { ICrabStrategy } from "../../oracles/crab/CrabOracle.sol";
import { UniswapV3Oracle } from "../../oracles/uniswap/UniswapV3Oracle.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";

contract CrabOracleTest is Test, TestConstants {
    CrabOracle public crabOracle;
    UniswapV3Oracle uniswapV3Oracle;
    address uniswapV3oSQTHPool = 0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C;
    address crabStrategyV2 = 0x3B960E47784150F5a63777201ee2B15253D713e8;
    address timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;

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
        vm.createSelectFork(MAINNET, 15974678);

        uniswapV3Oracle = UniswapV3Oracle(0x358538ea4F52Ac15C551f88C701696f6d9b38F3C);

        crabOracle = new CrabOracle(
            CRAB,
            OSQTH,
            ETH,
            ICrabStrategy(crabStrategyV2),
            IOracle(address(uniswapV3Oracle))
        );

        vm.startPrank(timelock);
        uniswapV3Oracle.grantRole(uniswapV3Oracle.setSource.selector, timelock);
        uniswapV3Oracle.setSource(ETH, OSQTH, uniswapV3oSQTHPool, 100);
        vm.stopPrank();
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        crabOracle = CrabOracle(vm.envAddress("ORACLE"));

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
        (uint256 amount, ) = crabOracle.peek(bytes32(CRAB), bytes32(ETH), 1e18);
        emit log_named_uint("Crab in ETH Value", amount);
        assertEq(amount, 962695640155633739);
    }

    function testPeekReversed() public onlyMock {
        (uint256 amount, ) = crabOracle.peek(bytes32(ETH), bytes32(CRAB), 1e18);
        emit log_named_uint("ETH in Crab Value", amount);
        assertEq(amount, 1038749900060143067);
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        (amount, updateTime) = crabOracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        assertApproxEqRel(amount, 1e18, 1e18);
    }
}
