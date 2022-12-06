// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "../../oracles/chainlink/ChainlinkUSDMultiOracle.sol";
import "../../oracles/chainlink/ChainlinkL2USDMultiOracle.sol";
import "../../oracles/chainlink/AggregatorV3Interface.sol";
import "../../mocks/oracles/chainlink/FlagsInterfaceMock.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3MockEx.sol";
import "../utils/TestConstants.sol";
import { TestExtensions } from "../TestExtensions.sol";

contract ChainlinkUSDMultiOracleTest is Test, TestConstants, TestExtensions {
    ChainlinkUSDMultiOracle public oracleL1;
    ChainlinkL2USDMultiOracle public oracleL2;
    FlagsInterfaceMock public flagsL2;
    ChainlinkAggregatorV3MockEx public aggregator;
    AggregatorV3Interface daiUsdAggregator = AggregatorV3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
    AggregatorV3Interface fraxUsdAggregator = AggregatorV3Interface(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public frax = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    function setUp() public {
        vm.createSelectFork(MAINNET, 15044600);

        oracleL1 = new ChainlinkUSDMultiOracle();
        flagsL2 = new FlagsInterfaceMock();
        oracleL2 = new ChainlinkL2USDMultiOracle(flagsL2);
        aggregator = new ChainlinkAggregatorV3MockEx(18);   // for testing non-8-digit source

        oracleL1.grantRole(oracleL1.setSource.selector, address(this));
        oracleL2.grantRole(oracleL2.setSource.selector, address(this));
    }

    function testSourceMustBeSet() public {
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

    function testDoesNotAllowNon8DigitSource() public {
        vm.expectRevert("Non-8-decimals USD source");
        oracleL1.setSource(DAI, ERC20(dai), address(aggregator));

        vm.expectRevert("Non-8-decimals USD source");
        oracleL2.setSource(DAI, ERC20(dai), address(aggregator));
    }

    function testGetConversion() public {
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

    function testCannotGetConversionIfSequencerDown() public {
        oracleL2.setSource(DAI, ERC20(dai), address(daiUsdAggregator));
        oracleL2.setSource(FRAX, ERC20(frax), address(fraxUsdAggregator));
        flagsL2.flagSetArbitrumSeqOffline(true);
        vm.expectRevert("Chainlink feeds are not being updated");
        oracleL2.peek(bytes32(DAI), bytes32(FRAX), WAD);
        flagsL2.flagSetArbitrumSeqOffline(false);
        oracleL2.peek(bytes32(DAI), bytes32(FRAX), WAD);
    }
}