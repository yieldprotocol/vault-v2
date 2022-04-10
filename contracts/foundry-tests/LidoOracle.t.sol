// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../oracles/composite/CompositeMultiOracle.sol";
import "../oracles/lido/LidoOracle.sol";
import "../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "../mocks/oracles/lido/WstETHMock.sol";
import "../mocks/ERC20Mock.sol";
import "../mocks/USDCMock.sol";
import "../mocks/WETH9Mock.sol";
import "./utils/Test.sol";
import "./utils/TestConstants.sol";

contract LidoOracleTest is Test, TestConstants, AccessControl {
    WETH9Mock public weth;
    ERC20Mock public steth;
    USDCMock public usdc;
    LidoOracle public lidoOracle;
    WstETHMock public lidoMock;
    ChainlinkMultiOracle public chainlinkMultiOracle;
    CompositeMultiOracle public compositeMultiOracle;
    ChainlinkAggregatorV3Mock public stethEthAggregator;
    ChainlinkAggregatorV3Mock public usdcEthAggregator;

    bytes6 public mockBytes6 = 0xd1eaa762fae7;

    function setUp() public {
        lidoMock = new WstETHMock();
        lidoMock.set(1008339308050006006);
        weth = new WETH9Mock();
        usdc = new USDCMock();
        steth = new ERC20Mock("Liquid staked Ether 2.0", "STETH");
        chainlinkMultiOracle = new ChainlinkMultiOracle();
        chainlinkMultiOracle.grantRole(0xef532f2e, address(this));
        stethEthAggregator = new ChainlinkAggregatorV3Mock();
        usdcEthAggregator = new ChainlinkAggregatorV3Mock();
        chainlinkMultiOracle.setSource(STETH, steth, ETH, weth, address(stethEthAggregator));
        chainlinkMultiOracle.setSource(USDC, usdc, ETH, weth, address(usdcEthAggregator));
        vm.warp(uint256(bytes32(mockBytes6)));
        stethEthAggregator.set(992415619690099500);
        usdcEthAggregator.set(WAD / 4000);
        lidoOracle = new LidoOracle(WSTETH, STETH);
        lidoOracle.grantRole(0xa8026912, address(this));
        lidoOracle.setSource(IWstETH(address(lidoMock)));
        compositeMultiOracle = new CompositeMultiOracle();
        bytes4[] memory roles = new bytes4[](2);
        roles[0] = 0x92b45d9c;
        roles[1] = 0x60509e5f;
        compositeMultiOracle.grantRoles(roles, address(this));
        compositeMultiOracle.setSource(WSTETH, STETH, IOracle(address(lidoOracle)));
        compositeMultiOracle.setSource(STETH, ETH, IOracle(address(chainlinkMultiOracle)));
        compositeMultiOracle.setSource(USDC, ETH, IOracle(address(chainlinkMultiOracle)));
        bytes6[] memory path = new bytes6[](1);
        path[0] = STETH;
        compositeMultiOracle.setPath(WSTETH, ETH, path);
        bytes6[] memory paths = new bytes6[](2);
        paths[0] = STETH;
        paths[1] = ETH;
        compositeMultiOracle.setPath(WSTETH, USDC, paths);
    }

    function testGetConversion() public {
        (uint256 stethWstethConversion,) = lidoOracle.get(STETH, WSTETH, WAD);
        require(stethWstethConversion == 991729660855795538);
        (uint256 wstethStethConversion,) = lidoOracle.get(WSTETH, STETH, 1e18);
        require(wstethStethConversion == 1008339308050006006);
    }

    function testRevertOnUnknownSource() public {
        vm.expectRevert("Source not found");
        lidoOracle.get(bytes32(DAI), bytes32(mockBytes6), WAD);
    }

    function testRetrieveDirectPairConversion() public view {
        (uint256 wstethStethConversion,) = compositeMultiOracle.peek(WSTETH, STETH, 1e18);
        require(wstethStethConversion == 1008339308050006006);
        (uint256 stethWstethConversion,) = compositeMultiOracle.peek(STETH, WSTETH, 1e18);
        require(stethWstethConversion == 991729660855795538);
        (uint256 stethEthConversion,) = compositeMultiOracle.peek(STETH, ETH, 1e18);
        require(stethEthConversion == 992415619690099500);
        (uint256 ethStethConversion,) = compositeMultiOracle.peek(ETH, STETH, 1e18);
        require(ethStethConversion == 1007642342743727538);
        (uint256 ethUsdcConversion,) = compositeMultiOracle.peek(ETH, USDC, 1e18);
        require(ethUsdcConversion == 4000000000);
        (uint256 usdcEthConversion,) = compositeMultiOracle.peek(USDC, ETH, 1e18);
        require(usdcEthConversion == 250000000000000000000000000);
    }

    function testRetrieveWSTETHToETHConversionAndReverse() public view {
        (uint256 wstethEthConversion,) = compositeMultiOracle.peek(WSTETH, ETH, 1e18);
        require(wstethEthConversion == 1000691679256332845);
        (uint256 ethWstethConversion,) = compositeMultiOracle.peek(ETH, WSTETH, 1e18);
        require(ethWstethConversion == 999308798833176199);
    }

    function testRetrieveWSTETHToUSDCConversionAndReverse() public view {
        (uint256 wstethUsdcConversion,) = compositeMultiOracle.peek(WSTETH, USDC, 1e18);
        require(wstethUsdcConversion == 4002766717);
        (uint256 usdcWstethConversion,) = compositeMultiOracle.peek(USDC, WSTETH, 1e18);
        require(usdcWstethConversion == 249827199708294049841946834);

    }

}
