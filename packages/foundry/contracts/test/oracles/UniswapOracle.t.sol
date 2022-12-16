// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../../oracles/uniswap/UniswapV3Oracle.sol";
import "../utils/TestConstants.sol";
import { TestExtensions } from "../utils/TestExtensions.sol";

contract UniswapOracleTest is Test, TestConstants, TestExtensions {
    UniswapV3Oracle public uniswapV3Oracle;

    bytes6 fraxId = 0x853d955acef8;
    bytes6 usdcId = 0xa0b86991c621;
    bytes6 wethId = 0xc02aaa39b223;
    bytes6 uniId = 0x1f9840a85d5a;
    bytes6 wbtcId = 0x2260fac5e554;

    address fraxUsdcPool = 0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52;
    address usdcEthPool = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
	address uniEthPool = 0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801;
	address wbtcUsdcPool = 0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35;

    
    function setUp() public {
        vm.createSelectFork(MAINNET, 15044600);

        uniswapV3Oracle = new UniswapV3Oracle();
        
        uniswapV3Oracle.grantRole(uniswapV3Oracle.setSource.selector, address(this));
        uniswapV3Oracle.setSource(fraxId, usdcId, fraxUsdcPool, 100);
        uniswapV3Oracle.setSource(usdcId, wethId, usdcEthPool, 100);
        uniswapV3Oracle.setSource(uniId, wethId, uniEthPool, 100);
        uniswapV3Oracle.setSource(wbtcId, usdcId, wbtcUsdcPool, 100);
    }

    function testFraxUsdcConversion() public {
        (uint256 fraxUsdcAmount,) = uniswapV3Oracle.get(bytes32(fraxId), bytes32(usdcId), 1e18);
        assertEq(fraxUsdcAmount / 1e6, 0, "FRAX/USDC conversion unsuccessful");
        (uint256 usdcFraxAmount,) = uniswapV3Oracle.get(bytes32(usdcId), bytes32(fraxId), 1000000);
        assertEq(usdcFraxAmount / 1e18, 1, "USDC/FRAX conversion unsuccessful");
    }

    function testUsdcEthConversion() public {
        (uint256 usdcWethAmount,) = uniswapV3Oracle.get(bytes32(usdcId), bytes32(wethId), 1000000);
        assertEq(usdcWethAmount / 1e9, 885240, "USDC/WETH conversion unsuccessful");    // will show USDC in terms of gwei
        (uint256 wethUsdcAmount,) = uniswapV3Oracle.get(bytes32(wethId), bytes32(usdcId), 1e18);
        assertEq(wethUsdcAmount / 1e6, 1129, "WETH/USDC conversion unsuccessful");
    }

    function testUniEthConversion() public {
        (uint256 uniWethAmount,) = uniswapV3Oracle.get(bytes32(uniId), bytes32(wethId), 1e18);
        assertEq(uniWethAmount / 1e9, 4368531, "UNI/WETH conversion unsuccessful");     // will show UNI in terms of gwei
        (uint256 wethUniAmount,) = uniswapV3Oracle.get(bytes32(wethId), bytes32(uniId), 1e18);
        assertEq(wethUniAmount / 1e18, 228, "WETH/UNI conversion unsuccessful"); 
    }

    function testWbtcUsdcConversion() public {
        (uint256 wbtcUsdcAmount,) = uniswapV3Oracle.get(bytes32(wbtcId), bytes32(usdcId), 100000000);
        assertEq(wbtcUsdcAmount / 1e6, 20078, "WBTC/USDC conversion unsuccessful");
        (uint256 usdcWbtcAmount,) = uniswapV3Oracle.get(bytes32(usdcId), bytes32(wbtcId), 1000000);
        assertEq(usdcWbtcAmount, 4980, "USDC/WBTC conversion unsuccessful");
    }
}