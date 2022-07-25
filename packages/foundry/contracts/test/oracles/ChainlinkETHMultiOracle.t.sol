// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../../oracles/chainlink/ChainlinkETHMultiOracle.sol";
import "../../mocks/oracles/OracleMock.sol";
import "../../oracles/chainlink/AggregatorV3Interface.sol";
import "../utils/TestConstants.sol";

contract ChainlinkMultiOracleTest is Test, TestConstants {
    OracleMock public oracleMock;
    ChainlinkETHMultiOracle public chainlinkOracle;
    AggregatorV3Interface daiEthAggregator = AggregatorV3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4);
    AggregatorV3Interface usdcEthAggregator = AggregatorV3Interface(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 public mockBytes32 = 0x0000000000000000000000000000000000000000000000000000000000000001;
    uint256 public oneUSDC = 1e6;

    function setUp() public {
        oracleMock = new OracleMock();
        daiEthAggregator = new ChainlinkAggregatorV3Mock();
        usdcEthAggregator = new ChainlinkAggregatorV3Mock();
        chainlinkOracle = new ChainlinkETHMultiOracle();

        vm.createSelectFork('mainnet', 15044600);
        chainlinkOracle.grantRole(chainlinkMultiOracle.setSource.selector, address(this));
        chainlinkOracle.setSource(DAI, dai, daiEthAggregator);
        chainlinkOracle.setSource(USDC, usdc, usdcEthAggregator);
    }

    function testGetConversion() public {
        oracleMock.set(WAD * 2);
        (uint256 oracleConversion,) = oracleMock.get(mockBytes32, mockBytes32, WAD);
        assertEq(oracleConversion, WAD * 2, "Get conversion unsuccessful");
    }

    function testRevertOnUnknownSource() public {
        vm.expectRevert("Source not found");
        chainlinkMultiOracle.get(bytes32(DAI), mockBytes32, WAD);
    }

    function testChainlinkMultiOracleConversion() public {
        (uint256 daiEthAmount,) = chainlinkMultiOracle.get(bytes32(DAI), bytes32(ETH), WAD * 2500);
        assertEq(daiEthAmount, WAD, "Get DAI-ETH conversion unsuccessful");
        (uint256 usdcEthAmount,) = chainlinkMultiOracle.get(bytes32(USDC), bytes32(ETH), oneUSDC * 2500);
        assertEq(usdcEthAmount, WAD, "Get USDC-ETH conversion unsuccessful");
        (uint256 ethDaiAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(DAI), WAD);
        assertEq(ethDaiAmount, WAD * 2500, "Get ETH-DAI conversion unsuccessful");
        (uint256 ethUsdcAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(USDC), WAD);
        assertEq(ethUsdcAmount, oneUSDC * 2500, "Get ETH-USDC conversion unsuccessful");
    }

    function testChainlinkMultiOracleConversionThroughEth() public {
        (uint256 daiUsdcAmount,) = chainlinkMultiOracle.get(bytes32(DAI), bytes32(USDC), WAD * 2500);
        assertEq(daiUsdcAmount, oneUSDC * 2500, "Get DAI-USDC conversion unsuccessful");
        (uint256 usdcDaiAmount,) = chainlinkMultiOracle.get(bytes32(USDC), bytes32(DAI), oneUSDC * 2500);
        assertEq(usdcDaiAmount, WAD * 2500, "Get USDC-DAI conversion unsuccessful");
    }
}
