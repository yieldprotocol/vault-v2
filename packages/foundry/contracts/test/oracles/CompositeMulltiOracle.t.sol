// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../../oracles/composite/CompositeMultiOracle.sol";
import "../../mocks/DAIMock.sol";
import "../../mocks/USDCMock.sol";
import "../../mocks/WETH9Mock.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "../utils/TestConstants.sol";

contract CompositeMultiOracleTest is Test, TestConstants, AccessControl {

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, IOracle indexed source);
    event PathSet(bytes6 indexed baseId, bytes6 indexed quoteId, bytes6[] indexed path);

    DAIMock public dai;
    USDCMock public usdc;
    WETH9Mock public weth;
    ChainlinkMultiOracle public chainlinkMultiOracle;
    CompositeMultiOracle public compositeMultiOracle;
    ChainlinkAggregatorV3Mock public daiEthAggregator; 
    ChainlinkAggregatorV3Mock public usdcEthAggregator;

    bytes32 public mockBytes32 = 0x0000000000000000000000000000000000000000000000000000000000000001;
    uint256 public oneUSDC = WAD / 1000000000000;
    bytes6[] public path = new bytes6[](1);

    function setUp() public {
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
        bytes4[] memory roles = new bytes4[](2);
        roles[0] = 0x92b45d9c;
        roles[1] = 0x60509e5f;
        compositeMultiOracle = new CompositeMultiOracle();
        compositeMultiOracle.grantRoles(roles, address(this));
    }

    function testSetSourceBothWays() public {
        bytes6 baseId = DAI;
        bytes6 quoteId = ETH;
        address source = address(chainlinkMultiOracle);
        assertEq(address(compositeMultiOracle.sources(baseId, quoteId)), 0x0000000000000000000000000000000000000000);
        vm.expectEmit(true, true, true, false);
        emit SourceSet(baseId, quoteId, IOracle(source));
        compositeMultiOracle.setSource(baseId, quoteId, IOracle(source));
    }

    function testSetPathAndReservePath() public {
        bytes6 baseId = DAI;
        bytes6 quoteId = ETH;
        path[0] = USDC;
        compositeMultiOracle.setSource(DAI, USDC, IOracle(address(chainlinkMultiOracle)));
        compositeMultiOracle.setSource(ETH, USDC, IOracle(address(chainlinkMultiOracle)));
        vm.expectEmit(true, true, true, false);
        emit PathSet(baseId, quoteId, path);
        compositeMultiOracle.setPath(baseId, quoteId, path);
        assertEq(compositeMultiOracle.paths(baseId, quoteId, 0), path[0]);
        assertEq(compositeMultiOracle.paths(quoteId, baseId, 0), path[0]);
    }

    function setChainlinkMultiOracleSource() public {
        compositeMultiOracle.setSource(DAI, ETH, IOracle(address(chainlinkMultiOracle)));
        compositeMultiOracle.setSource(USDC, ETH, IOracle(address(chainlinkMultiOracle)));
        path[0] = ETH;
        compositeMultiOracle.setPath(DAI, USDC, path);
    }

    function testRetrieveConversionAndUpdateTime() public {
        setChainlinkMultiOracleSource();
        (uint256 amount, uint256 updateTime) = compositeMultiOracle.peek(DAI, ETH, WAD);
        assertEq(amount, WAD / 2500, "Get conversion unsuccessful");
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        (uint256 usdcEthAmount,) = compositeMultiOracle.peek(USDC, ETH, oneUSDC);
        assertEq(usdcEthAmount, WAD / 2500, "Get USDC-ETH conversion unsuccessful");
        (uint256 ethDaiAmount,) = compositeMultiOracle.peek(ETH, DAI, WAD);
        assertEq(ethDaiAmount, WAD * 2500, "Get ETH-DAI conversion unsuccessful");
        (uint256 ethUsdcAmount,) = compositeMultiOracle.peek(ETH, USDC, WAD);
        assertEq(ethUsdcAmount, oneUSDC * 2500, "Get ETH-USDC conversion unsuccessful");
    }

    function testRevertOnTimestampGreaterThanCurrentBlock() public {
        setChainlinkMultiOracleSource();
        daiEthAggregator.setTimestamp(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        vm.expectRevert("Invalid updateTime");
        compositeMultiOracle.peek(DAI, ETH, WAD);
    }

    function testUseOldestTimestampFound() public {
        setChainlinkMultiOracleSource();
        daiEthAggregator.setTimestamp(1);
        usdcEthAggregator.setTimestamp(block.timestamp);
        (,uint256 updateTime) = compositeMultiOracle.peek(DAI, USDC, WAD);
        assertEq(updateTime, 1);
    }

    function testRetrieveDaiUsdcConversionAndReverse() public {
        setChainlinkMultiOracleSource();
        (uint256 daiUsdcAmount,) = compositeMultiOracle.peek(DAI, USDC, WAD);
        assertEq(daiUsdcAmount, oneUSDC);
        (uint256 usdcDaiAmount,) = compositeMultiOracle.peek(USDC, DAI, oneUSDC);
        assertEq(usdcDaiAmount, WAD); 
    }
}
