// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { IERC20 } from "@yield-protocol/utils-v2/src/token/IERC20.sol";
import { IERC20Metadata } from "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import { ChainlinkMultiOracle } from "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import { WETH9Mock } from "../../mocks/WETH9Mock.sol";
import { DAIMock } from "../../mocks/DAIMock.sol";
import { USDCMock } from "../../mocks/USDCMock.sol";
import { OffchainAggregatorMock } from "../../mocks/oracles/chainlink/OffchainAggregatorMock.sol";
import { ChainlinkAggregatorV3Mock } from "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import { OracleMock } from "../../mocks/oracles/OracleMock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";

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
        oracleMock = new OracleMock();
        dai = new DAIMock();
        usdc = new USDCMock();
        weth = new WETH9Mock();
        
        daiEthAggregator = new ChainlinkAggregatorV3Mock();
        usdcEthAggregator = new ChainlinkAggregatorV3Mock();
        // WAD / 2500 here represents the amount of ETH received for either 1 DAI or 1 USDC
        daiEthAggregator.set(WAD / 2500);
        usdcEthAggregator.set(WAD / 2500);

        chainlinkMultiOracle = new ChainlinkMultiOracle();
        chainlinkMultiOracle.grantRole(0xe3e3c622, address(this));
        chainlinkMultiOracle.setSource(DAI, dai, ETH, weth, address(daiEthAggregator), 1 days);
        chainlinkMultiOracle.setSource(USDC, usdc, ETH, weth, address(usdcEthAggregator), 1 days);
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        chainlinkMultiOracle = ChainlinkMultiOracle(vm.envAddress("ORACLE"));
        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        unitForBase = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForQuote = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testGetConversion() public onlyMock {
        oracleMock.set(WAD * 2);
        (uint256 oracleConversion,) = oracleMock.get(mockBytes32, mockBytes32, WAD);
        assertEq(oracleConversion, WAD * 2, "Get conversion unsuccessful");
    }

    function testRevertOnUnknownSource() public onlyMock {
        vm.expectRevert("Source not found");
        chainlinkMultiOracle.get(bytes32(DAI), bytes32(mockBytes6), WAD);
    }

    function testRevertPastHeartbeat() public onlyMock {
        daiEthAggregator.setTimestamp(0);
        vm.warp(2 days);
        vm.expectRevert("Heartbeat exceeded");
        chainlinkMultiOracle.get(bytes32(DAI), bytes32(ETH), WAD);
    }

    function testRevertBelowMinAnswer() public onlyMock {
        daiEthAggregator.set(1);
        vm.expectRevert("Below minAnswer");
        chainlinkMultiOracle.get(bytes32(DAI), bytes32(ETH), WAD);
    }

    function testRevertAboveMaxAnswer() public onlyMock {
        daiEthAggregator.set(type(uint128).max);
        vm.expectRevert("Above maxAnswer");
        chainlinkMultiOracle.get(bytes32(DAI), bytes32(ETH), WAD);
    }

    function testChainlinkMultiOracleConversion() public onlyMock {
        (uint256 daiEthAmount,) = chainlinkMultiOracle.get(bytes32(DAI), bytes32(ETH), WAD * 2500);
        assertEq(daiEthAmount, WAD, "Get DAI-ETH conversion unsuccessful");
        (uint256 usdcEthAmount,) = chainlinkMultiOracle.get(bytes32(USDC), bytes32(ETH), oneUSDC * 2500);
        assertEq(usdcEthAmount, WAD, "Get USDC-ETH conversion unsuccessful");
        (uint256 ethDaiAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(DAI), WAD);
        assertEq(ethDaiAmount, WAD * 2500, "Get ETH-DAI conversion unsuccessful");
        (uint256 ethUsdcAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(USDC), WAD);
        assertEq(ethUsdcAmount, oneUSDC * 2500, "Get ETH-USDC conversion unsuccessful");
    }

    function testChainlinkMultiOracleConversionThroughEth() public onlyMock {
        (uint256 daiUsdcAmount,) = chainlinkMultiOracle.get(bytes32(DAI), bytes32(USDC), WAD * 2500);
        assertEq(daiUsdcAmount, oneUSDC * 2500, "Get DAI-USDC conversion unsuccessful");
        (uint256 usdcDaiAmount,) = chainlinkMultiOracle.get(bytes32(USDC), bytes32(DAI), oneUSDC * 2500);
        assertEq(usdcDaiAmount, WAD * 2500, "Get USDC-DAI conversion unsuccessful");
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        (amount, updateTime) = chainlinkMultiOracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        assertApproxEqRel(amount, unitForQuote, unitForQuote * 10000);
        // and reverse
        (amount, updateTime) = chainlinkMultiOracle.peek(quote, base, unitForQuote);
        assertApproxEqRel(amount, unitForBase, unitForBase * 10000);
    }
}
