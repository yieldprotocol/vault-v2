// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../../oracles/composite/CompositeMultiOracle.sol";
import "../../oracles/lido/LidoOracle.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "../../mocks/oracles/lido/WstETHMock.sol";
import "../../mocks/ERC20Mock.sol";
import "../../mocks/USDCMock.sol";
import "../../mocks/WETH9Mock.sol";
import "../utils/TestConstants.sol";

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
        // amount of wstETH that you get for 1e18 stETH
        uint256 stethToWstethPrice = 1008339308050006006;
        lidoMock.set(stethToWstethPrice);
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
        // amount of ETH that you get for 1e18 stETH
        uint256 stethToEthPrice = 992415619690099500;
        stethEthAggregator.set(stethToEthPrice);
        // amount of ETH that you get for 1 USDC
        uint256 usdcToEthPrice = WAD / 4000;
        usdcEthAggregator.set(usdcToEthPrice);
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
        (uint256 stethWstethAmount,) = lidoOracle.get(STETH, WSTETH, WAD);
        uint256 stethToWstethPrice = 991729660855795538; // Amount of wstEth recieved for 1 stETH
        assertEq(stethWstethAmount, stethToWstethPrice);

        (uint256 wstethStethAmount,) = lidoOracle.get(WSTETH, STETH, WAD);
        uint256 wstethToStethPrice = 1008339308050006006; // Amount of stETH received for 1 wstETH
        assertEq(wstethStethAmount, wstethToStethPrice);
    }

    function testRevertOnUnknownSource() public {
        vm.expectRevert("Source not found");
        lidoOracle.get(bytes32(DAI), bytes32(mockBytes6), WAD);
    }

    function testRetrieveDirectPairConversion() public {
        (uint256 wstethStethAmount,) = compositeMultiOracle.peek(WSTETH, STETH, WAD);  
        uint256 wstethToStethPrice = 1008339308050006006; // Amount of stETH received for 1 wstETH
        assertEq(wstethStethAmount, wstethToStethPrice);

        (uint256 stethWstethAmount,) = compositeMultiOracle.peek(STETH, WSTETH, WAD);
        uint256 stethToWstethPrice = 991729660855795538; // Amount of wstETH received for 1 stETH
        assertEq(stethWstethAmount, stethToWstethPrice);

        (uint256 stethEthAmount,) = compositeMultiOracle.peek(STETH, ETH, WAD);
        uint256 stethToEthPrice = 992415619690099500; // Amount of ETH received for 1 stETH
        assertEq(stethEthAmount, stethToEthPrice);

        (uint256 ethStethAmount,) = compositeMultiOracle.peek(ETH, STETH, WAD);
        uint256 ethToStethPrice = 1007642342743727538; // Amount of stETH received for 1 ETH
        assertEq(ethStethAmount, ethToStethPrice);

        (uint256 ethUsdcAmount,) = compositeMultiOracle.peek(ETH, USDC, WAD);
        uint256 ethToUsdcPrice = 4000000000; // Amount of USDC received for 1 ETH
        assertEq(ethUsdcAmount, ethToUsdcPrice);

        (uint256 usdcEthAmount,) = compositeMultiOracle.peek(USDC, ETH, WAD);
        uint256 usdcToEthPrice = 250000000000000000000000000; // Amount of ETH received for 1 USDC
        assertEq(usdcEthAmount, usdcToEthPrice);
    }

    function testRetrieveWSTETHToETHConversionAndReverse() public {
        (uint256 wstethEthAmount,) = compositeMultiOracle.peek(WSTETH, ETH, WAD);
        uint256 wstethToEthPrice = 1000691679256332845; // Amount of ETH received for 1 wstETH 
        assertEq(wstethEthAmount, wstethToEthPrice);

        (uint256 ethWstethAmount,) = compositeMultiOracle.peek(ETH, WSTETH, WAD);
        uint256 ethToWstethPrice = 999308798833176199; // Amount of wstETH received for 1 ETH
        assertEq(ethWstethAmount, ethToWstethPrice);
    }

    function testRetrieveWSTETHToUSDCConversionAndReverse() public {
        (uint256 wstethUsdcAmount,) = compositeMultiOracle.peek(WSTETH, USDC, WAD);
        uint256 wstethToUsdcPrice = 4002766717; // Amount of USDC received for 1 wstETH
        assertEq(wstethUsdcAmount, wstethToUsdcPrice);

        (uint256 usdcWstethAmount,) = compositeMultiOracle.peek(USDC, WSTETH, WAD);
        uint256 usdcToWstethPrice = 249827199708294049841946834; // Amount of wstETH received for 1 USDC
        assertEq(usdcWstethAmount, usdcToWstethPrice);
    }

}
