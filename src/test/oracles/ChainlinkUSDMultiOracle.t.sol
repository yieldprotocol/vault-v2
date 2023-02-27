// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { ERC20 } from "@yield-protocol/utils-v2/src/token/ERC20.sol";
import { ChainlinkUSDMultiOracle } from "../../oracles/chainlink/ChainlinkUSDMultiOracle.sol";
import { ChainlinkL2USDMultiOracle } from "../../oracles/chainlink/ChainlinkL2USDMultiOracle.sol";
import { AggregatorV3Interface } from "../../oracles/chainlink/AggregatorV3Interface.sol";
import { FlagsInterfaceMock } from "../../mocks/oracles/chainlink/FlagsInterfaceMock.sol";
import { ChainlinkAggregatorV3MockEx } from "../../mocks/oracles/chainlink/ChainlinkAggregatorV3MockEx.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { TestExtensions } from "../utils/TestExtensions.sol";

contract ChainlinkUSDMultiOracleTest is Test, TestConstants, TestExtensions {
    ChainlinkUSDMultiOracle public oracleL1;
    ChainlinkL2USDMultiOracle public oracleL2;
    FlagsInterfaceMock public flagsL2;
    ChainlinkAggregatorV3MockEx public aggregator;
    AggregatorV3Interface daiUsdAggregator = AggregatorV3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
    AggregatorV3Interface fraxUsdAggregator = AggregatorV3Interface(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public frax = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

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
        vm.createSelectFork(MAINNET, 15044600);

        oracleL1 = new ChainlinkUSDMultiOracle();
        flagsL2 = new FlagsInterfaceMock();
        oracleL2 = new ChainlinkL2USDMultiOracle(flagsL2);
        aggregator = new ChainlinkAggregatorV3MockEx(18);   // for testing non-8-digit source

        oracleL1.grantRole(oracleL1.setSource.selector, address(this));
        oracleL2.grantRole(oracleL2.setSource.selector, address(this));
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        oracleL2 = ChainlinkL2USDMultiOracle(vm.envAddress("ORACLE"));

        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        unitForBase = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForQuote = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());

    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }


    function testSourceMustBeSet() public onlyMock {
        vm.expectRevert("Source not found");
        oracleL1.peek(bytes32(DAI), bytes32(FRAX), WAD);
        oracleL1.setSource(DAI, ERC20(dai), address(daiUsdAggregator));
        vm.expectRevert("Source not found");
        oracleL1.peek(bytes32(DAI), bytes32(FRAX), WAD);
        vm.expectRevert("Source not found");
        oracleL1.peek(bytes32(FRAX), bytes32(DAI), WAD);
        
        vm.expectRevert("Source not found");
        oracleL2.peek(bytes32(DAI), bytes32(FRAX), WAD);
        oracleL2.setSource(DAI, ERC20(dai), address(daiUsdAggregator));
        vm.expectRevert("Source not found");
        oracleL2.peek(bytes32(DAI), bytes32(FRAX), WAD);
        vm.expectRevert("Source not found");
        oracleL2.peek(bytes32(FRAX), bytes32(DAI), WAD);
    }

    function testDoesNotAllowNon8DigitSource() public onlyMock {
        vm.expectRevert("Non-8-decimals USD source");
        oracleL1.setSource(DAI, ERC20(dai), address(aggregator));

        vm.expectRevert("Non-8-decimals USD source");
        oracleL2.setSource(DAI, ERC20(dai), address(aggregator));
    }

    function testGetConversion() public onlyMock {
        uint256 amount;

        oracleL1.setSource(DAI, ERC20(dai), address(daiUsdAggregator));
        oracleL1.setSource(FRAX, ERC20(frax), address(fraxUsdAggregator));
        (amount,) = oracleL1.peek(bytes32(DAI), bytes32(FRAX), WAD);
        assertEq(amount, 1001719244434696556, "Conversion unsuccessful");
        (amount,) = oracleL1.peek(bytes32(FRAX), bytes32(DAI), WAD);
        assertEq(amount, 998283706293706293, "Conversion unsuccessful");

        oracleL2.setSource(DAI, ERC20(dai), address(daiUsdAggregator));
        oracleL2.setSource(FRAX, ERC20(frax), address(fraxUsdAggregator));
        (amount,) = oracleL2.peek(bytes32(DAI), bytes32(FRAX), WAD);
        assertEq(amount, 1001719244434696556, "Conversion unsuccessful");
        (amount,) = oracleL2.peek(bytes32(FRAX), bytes32(DAI), WAD);
        assertEq(amount, 998283706293706293, "Conversion unsuccessful");
    }

    function testCannotGetConversionIfSequencerDown() public onlyMock {
        oracleL2.setSource(DAI, ERC20(dai), address(daiUsdAggregator));
        oracleL2.setSource(FRAX, ERC20(frax), address(fraxUsdAggregator));
        flagsL2.flagSetArbitrumSeqOffline(true);
        vm.expectRevert("Chainlink feeds are not being updated");
        oracleL2.peek(bytes32(DAI), bytes32(FRAX), WAD);
        flagsL2.flagSetArbitrumSeqOffline(false);
        oracleL2.peek(bytes32(DAI), bytes32(FRAX), WAD);
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        (amount, updateTime) = oracleL2.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        assertApproxEqRel(amount, unitForQuote, unitForQuote * 10000);
        // and reverse
        (amount, updateTime) = oracleL2.peek(quote, base, unitForQuote);
        assertApproxEqRel(amount, unitForBase, unitForBase * 10000);
    }
}