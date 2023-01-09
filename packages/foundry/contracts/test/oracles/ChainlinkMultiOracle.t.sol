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

    function setUpHarness() public {
        chainlinkMultiOracle = ChainlinkMultiOracle(vm.envAddress("ORACLE"));
        ilkIdA = bytes6(vm.envBytes32("BASE"));
        ilkIdB = bytes6(vm.envBytes32("QUOTE"));
        unitForA = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForB = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
    }

    function setUp() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testGetConversion() public {
        (uint256 oracleConversion,) = chainlinkMultiOracle.get(bytes32(ilkIdA), bytes32(ilkIdB), unitForA);
        assertGt(oracleConversion, 0, "Get conversion unsuccessful");
    }

    function testRevertOnUnknownSource() public {
        bytes6 mockBytes6 = 0x000000000003;
        vm.expectRevert("Source not found");
        chainlinkMultiOracle.get(bytes32(ilkIdA), mockBytes6, unitForA);
    }

    function testChainlinkMultiOracleConversion() public {
        (uint256 aEthAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdA), bytes32(ETH), unitForA);
        assertGt(aEthAmount, 0, "Get base-quote conversion unsuccessful");
        (uint256 bEthAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdB), bytes32(ETH), unitForB);
        assertGt(bEthAmount, 0, "Get base-quote conversion unsuccessful");
        (uint256 ethAAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(ilkIdA), WAD);
        assertGt(ethAAmount, 0, "Get reverse base-quote conversion unsuccessful");
        (uint256 ethBAmount,) = chainlinkMultiOracle.get(bytes32(ETH), bytes32(ilkIdB), WAD);
        assertGt(ethBAmount, 0, "Get reverse base-quote conversion unsuccessful");
    }

    function testChainlinkMultiOracleConversionThroughEth() public {
        (uint256 aBAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdA), bytes32(ilkIdB), unitForA);
        assertGt(aBAmount, 0, "Get base-quote conversion through ETH unsuccessful");
        (uint256 bAAmount,) = chainlinkMultiOracle.get(bytes32(ilkIdB), bytes32(ilkIdA), unitForB);
        assertGt(bAAmount, 0, "Get base-quote conversion through ETH unsuccessful");
    }
}
