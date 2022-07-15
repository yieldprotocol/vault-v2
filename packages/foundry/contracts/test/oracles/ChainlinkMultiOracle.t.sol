// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../../mocks/DAIMock.sol";
import "../../mocks/USDCMock.sol";
import "../../mocks/WETH9Mock.sol";
import "../../mocks/oracles/OracleMock.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "../utils/TestConstants.sol";

contract ChainlinkMultiOracleTest is Test, TestConstants {
    OracleMock public oracleMock;
    DAIMock public dai;
    USDCMock public usdc;
    WETH9Mock public weth;
    ChainlinkMultiOracle public chainlinkMultiOracle;
    ChainlinkAggregatorV3Mock public daiEthAggregator;
    ChainlinkAggregatorV3Mock public usdcEthAggregator;

    bytes32 public mockBytes32 = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes6 public mockBytes6 = 0x000000000001;
    uint256 public oneUSDC = 1e6;

    function setUp() public {
        oracleMock = new OracleMock();
        dai = new DAIMock();
        usdc = new USDCMock();
        weth = new WETH9Mock();
        daiEthAggregator = new ChainlinkAggregatorV3Mock();
        usdcEthAggregator = new ChainlinkAggregatorV3Mock();
        chainlinkMultiOracle = new ChainlinkMultiOracle();
        chainlinkMultiOracle.grantRole(0xef532f2e, address(this));
        chainlinkMultiOracle.setSource(DAI, dai, ETH, weth, address(daiEthAggregator));
        chainlinkMultiOracle.setSource(USDC, usdc, ETH, weth, address(usdcEthAggregator));
        vm.warp(uint256(mockBytes32));
        // WAD / 2500 here represents the amount of ETH received for either 1 DAI or 1 USDC
        daiEthAggregator.set(WAD / 2500);
        usdcEthAggregator.set(WAD / 2500);
    }

    function testGetConversion() public {
        oracleMock.set(WAD * 2);
        (uint256 oracleConversion,) = oracleMock.get(mockBytes32, mockBytes32, WAD);
        assertEq(oracleConversion, WAD * 2, "Get conversion unsuccessful");
    }

    function testRevertOnUnknownSource() public {
        vm.expectRevert("Source not found");
        chainlinkMultiOracle.get(bytes32(DAI), bytes32(mockBytes6), WAD);
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
