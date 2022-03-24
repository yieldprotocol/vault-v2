// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../mocks/DAIMock.sol";
import "../mocks/USDCMock.sol";
import "../mocks/WETH9Mock.sol";
import "../mocks/oracles/OracleMock.sol";
import "../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "./utils/Test.sol";
import "./utils/TestConstants.sol";

contract ChainlinkMultiOracleTest is Test, TestConstants, AccessControl {
    OracleMock public oracleMock;
    DAIMock public dai;
    USDCMock public usdc;
    WETH9Mock public weth;
    ChainlinkMultiOracle public chainlinkMultiOracle;
    ChainlinkAggregatorV3Mock public daiEthAggregator; 
    ChainlinkAggregatorV3Mock public usdcEthAggregator;

    bytes32 public mockBytes32 = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes6 public mockBytes6 = 0x000000000001;
    uint256 public oneUSDC = WAD / 1000000000000;

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
        daiEthAggregator.set(WAD / 2500);
        usdcEthAggregator.set(WAD / 2500);
    }

    function testGetSpotPrice() public {
        oracleMock.set(WAD * 2);
        (uint256 oracleSpotPrice,) = oracleMock.get(mockBytes32, mockBytes32, WAD);
        require(oracleSpotPrice == WAD * 2, "Get spot price unsuccessful");
    }

    function testRevertOnUnknownSource() public {
        vm.expectRevert("Source not found");
        chainlinkMultiOracle.get(bytes32(DAI), bytes32(mockBytes6), WAD);
    }

    function testChainlinkMultiOracleSpotPrice() public {
        (uint256 daiEthSpotPrice,) = chainlinkMultiOracle.get(bytes32(DAI), bytes32(ETH), WAD * 2500);
        require(daiEthSpotPrice == WAD, "Get DAI-ETH spot price unsuccessful");
        (uint256 usdcEthSpotPrice,) = chainlinkMultiOracle.get(bytes32(USDC), bytes32(ETH), oneUSDC * 2500);
        require(usdcEthSpotPrice == WAD, "Get USDC-ETH spot price unsuccessful");
        (uint256 ethDaiSpotPrice,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(DAI), WAD);
        require(ethDaiSpotPrice == WAD * 2500, "Get ETH-DAI spot price unsuccessful");
        (uint256 ethUsdcSpotPrice,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(USDC), WAD);
        require(ethUsdcSpotPrice == oneUSDC * 2500, "Get ETH-USDC spot price unsuccessful");
    }

    function testChainlinkMultiOracleSpotPriceThroughEth() public {
        (uint256 daiUsdcSpotPrice,) = chainlinkMultiOracle.get(bytes32(DAI), bytes32(USDC), WAD * 2500);
        require(daiUsdcSpotPrice == oneUSDC * 2500, "Get DAI-USDC spot price unsuccessful");
        (uint256 usdcDaiSpotPrice,) = chainlinkMultiOracle.get(bytes32(USDC), bytes32(DAI), oneUSDC * 2500);
        require(usdcDaiSpotPrice == WAD * 2500, "Get USDC-DAI spot price unsuccessful");
    }
}