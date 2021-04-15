// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./OracleMock.sol";
import "../oracles/UniswapV2TWAPOracle.sol";

/**
 * @title MockUniswapV2TWAPOracle
 * @author Jacob Eliosoff (@jacob-eliosoff)
 * @notice A Uniswap V2 TWAP Oracle whose price we can override.  Testing purposes only!
 */
contract MockUniswapV2TWAPOracle is UniswapV2TWAPOracle, OracleMock {
    constructor(IUniswapV2Pair pair, uint tokenToUse, int tokenDecimals) UniswapV2TWAPOracle(pair, tokenToUse, tokenDecimals) {}

    function get() public override(UniswapV2TWAPOracle, OracleMock) returns (uint price, uint updateTime) {
        (price, updateTime) = (spot != 0) ? (spot, updated) : super.get();
    }

    function peek() public override(UniswapV2TWAPOracle, OracleMock) view returns (uint price, uint updateTime) {
        (price, updateTime) = (spot != 0) ? (spot, updated) : super.peek();
    }
}
