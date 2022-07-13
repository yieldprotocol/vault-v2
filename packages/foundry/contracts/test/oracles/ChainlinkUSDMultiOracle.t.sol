// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "../../oracles/chainlink/ChainlinkUSDMultiOracle.sol";
import "../../oracles/chainlink/ChainlinkL2USDMultiOracle.sol";
import "../../mocks/oracles/chainlink/FlagsInterfaceMock.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3MockEx.sol";
import "../utils/TestConstants.sol";

contract ChainlinkUSDMultiOracleTest is Test, TestConstants {
    ChainlinkUSDMultiOracle public oracleL1;
    ChainlinkL2USDMultiOracle public oracleL2;
    FlagsInterfaceMock public flagsL2;
    ChainlinkAggregatorV3MockEx public daiFraxAggregator;

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public frax = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    function setUp() public {
        oracleL1 = new ChainlinkUSDMultiOracle();
        flagsL2 = new FlagsInterfaceMock();
        oracleL2 = new ChainlinkL2USDMultiOracle(flagsL2);
        daiFraxAggregator = new ChainlinkAggregatorV3MockEx(8);

        oracleL1.grantRole(oracleL1.setSource.selector, address(this));
        oracleL2.grantRole(oracleL2.setSource.selector, address(this));
    }

    function testSourceMustBeSet() public {
        vm.expectRevert("Source not found");
        oracleL1.peek(DAI, FRAX, WAD);
        vm.expectRevert("Source not found");
        oracleL2.peek(DAI, FRAX, WAD);

        oracleL1.setSource(DAI, ERC20(dai), address(daiFraxAggregator));
        vm.expectRevert("Source not found");
        oracleL1.peek(FRAX, DAI, WAD);
    }
}