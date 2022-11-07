// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/strategy/StrategyOracle.sol";
import "../../interfaces/IStrategy.sol";

contract StrategyOracleTest is Test {
    StrategyOracle public strategyOracle;
    bytes6 baseId = 0xc02aaa39b223;
    bytes6 quoteId; // = 0x1f9840a85d5a;

    function setUp() public {
        vm.createSelectFork('mainnet', 15917726);

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

    function testPeek() public {
        (uint256 amount, ) = strategyOracle.peek(
            bytes32(baseId),
            bytes32(quoteId),
            1e18
        );
        assertEq(amount, 1000626265483608379);
    }

    function testPeekReversed() public {
        (uint256 amount, ) = strategyOracle.peek(
            bytes32(quoteId),
            bytes32(baseId),
            1e18
        );
        assertEq(amount, 999374126479374692);
    }
}
