// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { IERC20 } from "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { IERC20Metadata } from "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import { ChainlinkMultiOracle } from "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import { WETH9Mock } from "../../mocks/WETH9Mock.sol";
import { ChainlinkAggregatorV3Mock } from "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";

contract ChainlinkMultiOracleTest is Test, TestConstants {
    WETH9Mock public weth;
    ChainlinkMultiOracle public chainlinkMultiOracle;
    ChainlinkAggregatorV3Mock public aEthAggregator;
    ChainlinkAggregatorV3Mock public bEthAggregator;
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint128 public unitForA;
    uint128 public unitForB;
    bytes6 public ilkIdA;
    bytes6 public ilkIdB;

    uint256 public oneUSDC = 1e6;

    function setUpMock() public {
        chainlinkMultiOracle = new ChainlinkMultiOracle();
        chainlinkMultiOracle.grantRole(chainlinkMultiOracle.setSource.selector, address(this));

        tokenA = IERC20(address(new ERC20Mock("", "")));
        tokenB = IERC20(address(new ERC20Mock("", "")));
        unitForA = uint128(10 ** ERC20Mock(address(tokenA)).decimals());
        unitForB = uint128(10 ** ERC20Mock(address(tokenB)).decimals());
        ilkIdA = 0x000000000001;
        ilkIdB = 0x000000000002;
        weth = new WETH9Mock();
        aEthAggregator = new ChainlinkAggregatorV3Mock();
        bEthAggregator = new ChainlinkAggregatorV3Mock();

        chainlinkMultiOracle.setSource(
            ilkIdA, 
            IERC20Metadata(address(tokenA)), 
            ETH, 
            weth, 
            address(aEthAggregator)
        );
        chainlinkMultiOracle.setSource(
            ilkIdB, 
            IERC20Metadata(address(tokenB)), 
            ETH, 
            weth, 
            address(bEthAggregator)
        );
        aEthAggregator.set(unitForA / 2500);
        bEthAggregator.set(unitForB / 2500);
    }

    function setUpHarness(string memory network) public {
        chainlinkMultiOracle = ChainlinkMultiOracle(vm.envAddress("ORACLE"));
        ilkIdA = bytes6(vm.envBytes32("BASE"));
        ilkIdB = bytes6(vm.envBytes32("QUOTE"));
        unitForA = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForB = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
    }

    function setUp() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);
        string memory network = vm.envOr(NETWORK, LOCALHOST);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);
    }

    function testGetConversion() public {
        (uint256 oracleConversion,) = chainlinkMultiOracle.get(bytes32(ilkIdA), bytes32(ilkIdB), unitForA);
        assertEq(oracleConversion, unitForA, "Get conversion unsuccessful");
    }

    function testRevertOnUnknownSource() public {
        bytes6 mockBytes6 = 0x000000000003;
        vm.expectRevert("Source not found");
        chainlinkMultiOracle.get(bytes32(ilkIdA), mockBytes6, unitForA);
    }

    function testChainlinkMultiOracleConversion() public {
        (uint256 aEthAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdA), bytes32(ETH), unitForA * 2500);
        assertEq(aEthAmount, WAD, "Get base-quote conversion unsuccessful");
        (uint256 bEthAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdB), bytes32(ETH), unitForB * 2500);
        assertEq(bEthAmount, WAD, "Get base-quote conversion unsuccessful");
        (uint256 ethAAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(ilkIdA), WAD);
        assertEq(ethAAmount, unitForA * 2500, "Get reverse base-quote conversion unsuccessful");
        (uint256 ethBAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(ilkIdB), WAD);
        assertEq(ethBAmount, unitForB * 2500, "Get reverse base-quote conversion unsuccessful");
    }

    function testChainlinkMultiOracleConversionThroughEth() public {
        (uint256 aBAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdA), bytes32(ilkIdB), unitForA * 2500);
        assertEq(aBAmount, unitForB * 2500, "Get DAI-USDC conversion unsuccessful");
        (uint256 bAAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdB), bytes32(ilkIdA), unitForB * 2500);
        assertEq(bAAmount, unitForA * 2500, "Get USDC-DAI conversion unsuccessful");
    }
}
