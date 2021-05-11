// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ISourceMock.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";


contract UniswapV3PoolMock is ISourceMock, IUniswapV3PoolImmutables {

    uint public price;

    function set(uint price_) external override {
        price = price_;
    }

    function factory() public pure override returns (address) {
        return address(0);
    }
    
    function token0() public pure override returns (address) {
        return address(0);
    }

    function token1() public pure override returns (address) {
        return address(0);
    }

    function fee() public pure override returns (uint24) {
        return 0;
    }

    function tickSpacing() public pure override returns (int24) {
        return 0;
    }

    function maxLiquidityPerTick() public pure override returns (uint128) {
        return 0;
    }
}