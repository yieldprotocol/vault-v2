// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { AccessControl } from "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import { ChainlinkMultiOracle } from "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import { CompositeMultiOracle } from "../../oracles/composite/CompositeMultiOracle.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { WETH9Mock } from "../../mocks/WETH9Mock.sol";
import { DAIMock } from "../../mocks/DAIMock.sol";
import { USDCMock } from "../../mocks/USDCMock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { OffchainAggregatorMock } from "../../mocks/oracles/chainlink/OffchainAggregatorMock.sol";
import { ChainlinkAggregatorV3Mock } from "../../mocks/oracles/chainlink/ChainlinkAggregatorV3MockEx.sol";
import { TestConstants } from "../utils/TestConstants.sol";

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
        dai = new DAIMock();
        usdc = new USDCMock();
        weth = new WETH9Mock();
        daiEthAggregator = new ChainlinkAggregatorV3Mock();
        usdcEthAggregator = new ChainlinkAggregatorV3Mock();
        daiEthAggregator.set(WAD / 2500);
        usdcEthAggregator.set(WAD / 2500);
        chainlinkMultiOracle = new ChainlinkMultiOracle();
        chainlinkMultiOracle.grantRole(0xe3e3c622, address(this));
        chainlinkMultiOracle.setSource(DAI, dai, ETH, weth, address(daiEthAggregator), 1 days);
        chainlinkMultiOracle.setSource(USDC, usdc, ETH, weth, address(usdcEthAggregator), 1 days);
        // WAD / 2500 here represents the amount of ETH received for either 1 DAI or 1 USDC
        bytes4[] memory roles = new bytes4[](2);
        roles[0] = 0x92b45d9c;
        roles[1] = 0x60509e5f;
        compositeMultiOracle = new CompositeMultiOracle();
        compositeMultiOracle.grantRoles(roles, address(this));
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        compositeMultiOracle = CompositeMultiOracle(vm.envAddress("ORACLE"));
        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        unitForBase = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForQuote = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testSetSourceBothWays() public onlyMock {
        bytes6 baseId = DAI;
        bytes6 quoteId = ETH;
        address source = address(chainlinkMultiOracle);
        assertEq(address(compositeMultiOracle.sources(baseId, quoteId)), 0x0000000000000000000000000000000000000000);
        vm.expectEmit(true, true, true, false);
        emit SourceSet(baseId, quoteId, IOracle(source));
        compositeMultiOracle.setSource(baseId, quoteId, IOracle(source));
    }

    function testSetPathAndReservePath() public onlyMock {
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

    function setChainlinkMultiOracleSource() public onlyMock {
        compositeMultiOracle.setSource(DAI, ETH, IOracle(address(chainlinkMultiOracle)));
        compositeMultiOracle.setSource(USDC, ETH, IOracle(address(chainlinkMultiOracle)));
        path[0] = ETH;
        compositeMultiOracle.setPath(DAI, USDC, path);
    }

    function testRetrieveConversionAndUpdateTime() public onlyMock {
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

// This test is not possible with the current setup of underlying chainlink oracles
//    function testRevertOnTimestampGreaterThanCurrentBlock() public onlyMock {
//        setChainlinkMultiOracleSource();
//        daiEthAggregator.setTimestamp(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
//        vm.expectRevert("Invalid updateTime");
//        compositeMultiOracle.peek(DAI, ETH, WAD);
//    }

    function testUseOldestTimestampFound() public onlyMock {
        setChainlinkMultiOracleSource();
        uint256 timestamp = block.timestamp;
        daiEthAggregator.setTimestamp(timestamp - 1);
        usdcEthAggregator.setTimestamp(timestamp);
        (,uint256 updateTime) = compositeMultiOracle.peek(DAI, USDC, WAD);
        assertEq(updateTime, timestamp - 1);
    }

    function testRetrieveDaiUsdcConversionAndReverse() public onlyMock {
        setChainlinkMultiOracleSource();
        (uint256 daiUsdcAmount,) = compositeMultiOracle.peek(DAI, USDC, WAD);
        assertEq(daiUsdcAmount, oneUSDC);
        (uint256 usdcDaiAmount,) = compositeMultiOracle.peek(USDC, DAI, oneUSDC);
        assertEq(usdcDaiAmount, WAD); 
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        (amount, updateTime) = compositeMultiOracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        assertApproxEqRel(amount, unitForQuote, unitForQuote * 10000);
        // and reverse
        (amount, updateTime) = compositeMultiOracle.peek(quote, base, unitForQuote);
        assertApproxEqRel(amount, unitForBase, unitForBase * 10000);
    }
}