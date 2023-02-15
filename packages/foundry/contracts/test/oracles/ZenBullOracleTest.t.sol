// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/opyn/ZenBullOracle.sol";
import {IZenBullStrategy} from "../../oracles/opyn/ZenBullOracle.sol";
import "../../oracles/uniswap/UniswapV3Oracle.sol";
import "../utils/TestConstants.sol";
import {wadPow, wadDiv} from "solmate/src/utils/SignedWadMath.sol";

contract ZenBullOracleTest is Test, TestConstants {
    ZenBullOracle public zenBullOracle;

    ICrabStrategy crabStrategy_ =
        ICrabStrategy(0x3B960E47784150F5a63777201ee2B15253D713e8);
    IZenBullStrategy zenBullStrategy_ =
        IZenBullStrategy(0xb46Fb07b0c80DBC3F97cae3BFe168AcaD46dF507);
    IUniswapV3PoolState osqthWethPool_ =
        IUniswapV3PoolState(0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C);
    IUniswapV3PoolState wethUsdcPool_ =
        IUniswapV3PoolState(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
    IERC20 eulerDToken_ = IERC20(0x84721A3dB22EB852233AEAE74f9bC8477F8bcc42);
    IERC20 eulerEToken_ = IERC20(0x1b808F49ADD4b8C6b5117d9681cF7312Fcf0dC1D);

    function setUp() public {
        vm.createSelectFork(MAINNET, 16468440);
        zenBullOracle = new ZenBullOracle(
            crabStrategy_,
            zenBullStrategy_,
            osqthWethPool_,
            wethUsdcPool_,
            eulerDToken_,
            eulerEToken_,
            USDC,
            ZENBULL
        );
    }

    function testPeek() public {
        (uint256 amount, ) = zenBullOracle.peek(
            bytes32(ZENBULL),
            bytes32(USDC),
            1e18
        );
        emit log_named_uint("Zenbull in USDC Value", amount);
        assertEq(amount, 3475041114);
    }

    function testPeekReversed() public {
        (uint256 amount, ) = zenBullOracle.peek(
            bytes32(USDC),
            bytes32(ZENBULL),
            1e6
        );
        emit log_named_uint("USDC in Zenbull Value", amount);
        assertEq(amount, 287766379503042);
    }
}
