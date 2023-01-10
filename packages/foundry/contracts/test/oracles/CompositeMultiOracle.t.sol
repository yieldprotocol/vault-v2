// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { IERC20 } from "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { IERC20Metadata } from "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { ChainlinkMultiOracle } from "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import { CompositeMultiOracle } from "../../oracles/composite/CompositeMultiOracle.sol";
import { WETH9Mock } from "../../mocks/WETH9Mock.sol";
import { ChainlinkAggregatorV3Mock } from "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";

contract CompositeMultiOracleTest is Test, TestConstants {

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, IOracle indexed source);
    event PathSet(bytes6 indexed baseId, bytes6 indexed quoteId, bytes6[] indexed path);

    WETH9Mock public weth;
    ChainlinkMultiOracle public chainlinkMultiOracle;
    CompositeMultiOracle public compositeMultiOracle;
    ChainlinkAggregatorV3Mock public aEthAggregator; 
    ChainlinkAggregatorV3Mock public bEthAggregator;
    address timelock;
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint128 public unitForA;
    uint128 public unitForB;
    bytes6 public ilkIdA;
    bytes6 public ilkIdB;
    bytes6[] public path = new bytes6[](1);

    modifier onlyMock() {
        if (!vm.envOr(MOCK, true)) return;
        _;
    }

    function setUpMock() public {
        chainlinkMultiOracle = new ChainlinkMultiOracle();
        chainlinkMultiOracle.grantRole(ChainlinkMultiOracle.setSource.selector, address(this));

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

        compositeMultiOracle = new CompositeMultiOracle();
        compositeMultiOracle.grantRole(CompositeMultiOracle.setSource.selector, address(this));
        compositeMultiOracle.grantRole(CompositeMultiOracle.setPath.selector, address(this));
        compositeMultiOracle.grantRole(CompositeMultiOracle.peek.selector, address(this));
    }

    function setUpHarness(string memory network) public {
        timelock = addresses[network][TIMELOCK];

        chainlinkMultiOracle = ChainlinkMultiOracle(vm.envAddress("CHAINLINK_ORACLE"));
        compositeMultiOracle = CompositeMultiOracle(vm.envAddress("COMPOSITE_ORACLE"));
        ilkIdA = bytes6(vm.envBytes32("BASE"));
        ilkIdB = bytes6(vm.envBytes32("QUOTE"));
        unitForA = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        unitForB = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
    
        vm.startPrank(timelock);
        compositeMultiOracle.grantRole(compositeMultiOracle.setSource.selector, address(this));
        compositeMultiOracle.grantRole(compositeMultiOracle.setPath.selector, address(this));
        vm.stopPrank();
    }

    function setUp() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);
        string memory network = vm.envOr(NETWORK, LOCALHOST);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);

        vm.label(address(chainlinkMultiOracle), "chainlinkMultiOracle");
        vm.label(address(compositeMultiOracle), "compositeMultiOracle");
    }


    function testSetSourceBothWays() public onlyMock {
        address source = address(chainlinkMultiOracle);
        assertEq(address(compositeMultiOracle.sources(ilkIdA, ilkIdB)), 0x0000000000000000000000000000000000000000);
        vm.expectEmit(true, true, true, false);
        emit SourceSet(ilkIdA, ilkIdB, IOracle(source));
        compositeMultiOracle.setSource(ilkIdA, ilkIdB, IOracle(source));
    }

    function testSetPathAndReservePath() public {
        path[0] = ilkIdB;
        compositeMultiOracle.setSource(ilkIdA, ilkIdB, IOracle(address(chainlinkMultiOracle)));
        compositeMultiOracle.setSource(ETH, ilkIdB, IOracle(address(chainlinkMultiOracle)));
        vm.expectEmit(true, true, true, false);
        emit PathSet(ilkIdA, ETH, path);
        compositeMultiOracle.setPath(ilkIdA, ETH, path);
        assertEq(compositeMultiOracle.paths(ilkIdA, ETH, 0), ilkIdB);
        assertEq(compositeMultiOracle.paths(ETH, ilkIdA, 0), ilkIdB);
    }

    function setChainlinkMultiOracleSource() public {
        compositeMultiOracle.setSource(ilkIdA, ETH, IOracle(address(chainlinkMultiOracle)));
        compositeMultiOracle.setSource(ilkIdB, ETH, IOracle(address(chainlinkMultiOracle)));
        path[0] = ETH;
        compositeMultiOracle.setPath(ilkIdA, ilkIdB, path);
    }

    function testRetrieveConversionAndUpdateTime() public {
        setChainlinkMultiOracleSource();
        (uint256 amount, uint256 updateTime) = compositeMultiOracle.peek(ilkIdA, ETH, unitForA);
        // https://github.com/yieldprotocol/bugs/issues/2
        // assertGt(amount, 0, "Get conversion unsuccessful");
        // assertGt(updateTime, 0, "Update time below lower bound");
        // assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        (uint256 tokenBEthAmount,) = compositeMultiOracle.peek(ilkIdB, ETH, unitForB);
        assertGt(tokenBEthAmount, 0, "Get TokenB-ETH conversion unsuccessful");
        (uint256 ethTokenAAmount,) = compositeMultiOracle.peek(ETH, ilkIdA, WAD);
        assertGt(ethTokenAAmount, 0, "Get ETH-TokenA conversion unsuccessful");
        (uint256 ethTokenBBAmount,) = compositeMultiOracle.peek(ETH, ilkIdB, WAD);
        assertGt(ethTokenBBAmount, 0, "Get ETH-TokenB conversion unsuccessful");
    }

    function testRevertOnTimestampGreaterThanCurrentBlock() public onlyMock {
        setChainlinkMultiOracleSource();
        aEthAggregator.setTimestamp(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        vm.expectRevert("Invalid updateTime");
        compositeMultiOracle.peek(ilkIdA, ETH, unitForA);
    }

    function testUseOldestTimestampFound() public onlyMock {
        setChainlinkMultiOracleSource();
        aEthAggregator.setTimestamp(1);
        bEthAggregator.setTimestamp(block.timestamp);
        (,uint256 updateTime) = compositeMultiOracle.peek(ilkIdA, ilkIdB, unitForA);
        assertEq(updateTime, 1);
    }

    function testRetrieveilkIdAilkIdBConversionAndReverse() public {
        setChainlinkMultiOracleSource();
        (uint256 tokenATokenBAmount,) = compositeMultiOracle.peek(ilkIdA, ilkIdB, unitForA);
        assertGt(tokenATokenBAmount, 0);
        (uint256 tokenBTokenAAmount,) = compositeMultiOracle.peek(ilkIdB, ilkIdA, unitForB);
        assertGt(tokenBTokenAAmount, 0); 
    }
}
