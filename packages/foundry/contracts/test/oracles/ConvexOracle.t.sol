// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { ERC20 } from "@yield-protocol/utils-v2/src/token/ERC20.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { ChainlinkMultiOracle } from "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import { CompositeMultiOracle } from "../../oracles/composite/CompositeMultiOracle.sol";
import { Cvx3CrvOracle } from "../../oracles/convex/Cvx3CrvOracle.sol";
import { AggregatorV3Interface } from "../../oracles/chainlink/AggregatorV3Interface.sol";
import { ICurvePool } from "../../oracles/convex/ICurvePool.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { TestExtensions } from "../utils/TestExtensions.sol";

contract ConvexOracleTest is Test, TestConstants, TestExtensions {
    Cvx3CrvOracle public convexOracle;
    ChainlinkMultiOracle public chainlinkMultiOracle;
    CompositeMultiOracle public compositeMultiOracle;
    ICurvePool public curvePool = ICurvePool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7); // Curve 3pool address

    // Chainlink price feeds
    AggregatorV3Interface public daiEthAggregator = AggregatorV3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4);
    AggregatorV3Interface public usdcEthAggregator = AggregatorV3Interface(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);
    AggregatorV3Interface public usdtEthAggregator = AggregatorV3Interface(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46);

    // Token addresses
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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

        convexOracle = new Cvx3CrvOracle();
        chainlinkMultiOracle = new ChainlinkMultiOracle();
        compositeMultiOracle = new CompositeMultiOracle();
        
        convexOracle.grantRole(
            convexOracle.setSource.selector, 
            address(this)
        );
        convexOracle.setSource(
            CVX3CRV, 
            ETH, 
            curvePool, 
            daiEthAggregator, 
            usdcEthAggregator, 
            usdtEthAggregator
        );

        chainlinkMultiOracle.grantRole(
            chainlinkMultiOracle.setSource.selector, 
            address(this)
        );
        chainlinkMultiOracle.setSource(
            DAI, 
            ERC20(dai), 
            ETH, 
            ERC20(weth), 
            address(daiEthAggregator)
        );
        chainlinkMultiOracle.setSource(
            USDC, 
            ERC20(usdc), 
            ETH, 
            ERC20(weth), 
            address(usdcEthAggregator)
        );

        bytes4[] memory roles = new bytes4[](2);
        roles[0] = compositeMultiOracle.setSource.selector;
        roles[1] = compositeMultiOracle.setPath.selector;
        compositeMultiOracle.grantRoles(roles, address(this));
        compositeMultiOracle.setSource(
            CVX3CRV, 
            ETH, 
            IOracle(address(convexOracle))
        );
        compositeMultiOracle.setSource(
            DAI, 
            ETH, 
            IOracle(address(chainlinkMultiOracle))
        );
        compositeMultiOracle.setSource(
            USDC, 
            ETH, 
            IOracle(address(chainlinkMultiOracle))
        );
        bytes6[] memory path = new bytes6[](1);
        path[0] = ETH;
        compositeMultiOracle.setPath(DAI, CVX3CRV, path);
        compositeMultiOracle.setPath(USDC, CVX3CRV, path);
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        convexOracle = Cvx3CrvOracle(0x52e860327bCc464014259A7cD16DaA5763d7Dc99);

        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        console.log("here");
        unitForBase = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
        console.log("here");

        unitForQuote = uint128(10 ** ERC20Mock(address(vm.envAddress("QUOTE_ADDRESS"))).decimals());
        console.log("here");
    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testCvx3CrvEthConversionAndReverse() public onlyMock {
        (uint256 cvx3crvEthAmount,) = compositeMultiOracle.peek(CVX3CRV, ETH, WAD);
        assertEq(cvx3crvEthAmount, 902489784942936, "Conversion unsuccessful");
        (uint256 ethCvx3CrvAmount,) = compositeMultiOracle.peek(ETH, CVX3CRV, WAD);
        assertEq(ethCvx3CrvAmount, 1108045782549471764420, "Conversion unsuccessful");
    }

    function testRetrieveDirectPairsConversion() public {
        (uint256 daiEthAmount,) = compositeMultiOracle.peek(DAI, ETH, WAD);
        assertEq(daiEthAmount, 887629605268503, "Conversion unsuccessful");
        (uint256 ethDaiAmount,) = compositeMultiOracle.peek(ETH, DAI, WAD);
        assertEq(ethDaiAmount, 1126596041935200643687, "Conversion unsuccessful");

        (uint256 usdcEthAmount,) = compositeMultiOracle.peek(USDC, ETH, 1e6);
        assertEq(usdcEthAmount, 888934300000000, "Conversion unsuccessful");
        (uint256 ethUsdcAmount,) = compositeMultiOracle.peek(ETH, USDC, WAD);
        assertEq(ethUsdcAmount, 1124942529, "Conversion unsuccessful");
    }

    function testCvx3CrvDaiConversionAndReverse() public onlyMock {
        (uint256 cvx3crvDaiAmount,) = compositeMultiOracle.peek(CVX3CRV, DAI, WAD);
        assertEq(cvx3crvDaiAmount, 1016741419603662136, "Conversion unsuccessful");
        (uint256 daiCvx3CrvAmount,) = compositeMultiOracle.peek(DAI, CVX3CRV, WAD);
        assertEq(daiCvx3CrvAmount, 983534240583817131, "Conversion unsuccessful");
    }

    function testCvx3CrvUsdcConversionAndReverse() public onlyMock {
        (uint256 cvx3crvUsdcAmount,) = compositeMultiOracle.peek(CVX3CRV, USDC, WAD);
        assertEq(cvx3crvUsdcAmount, 1015249, "Conversion unsuccessful");
        (uint256 usdcCvx3CrvAmount,) = compositeMultiOracle.peek(USDC, CVX3CRV, 1e6);
        assertEq(usdcCvx3CrvAmount, 984979902078566898, "Conversion unsuccessful");
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        (amount, updateTime) = convexOracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");

        // if (base == bytes6(ETH)) {
        //     (amount,) = convexOracle.peek(bytes32(base), bytes32(quote), unitForBase);
        //     assertLe(amount, 10000 * unitForQuote, "Conversion unsuccessful");
        //     assertGe(amount, 100 * unitForQuote, "Conversion unsuccessful");
        // } else {
        //     (amount,) = convexOracle.peek(bytes32(base), bytes32(quote), unitForBase);
        //     assertLe(amount, unitForQuote / 100, "Conversion unsuccessful");
        //     assertGe(amount, unitForQuote / 10000, "Conversion unsuccessful");
        // }
    }
}