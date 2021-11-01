// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import '../ISourceMock.sol';

contract LidoMock is ISourceMock {
    uint256 public price;

    function set(uint256 price_) external override {
        price = price_;
    }

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256) {
        return (_stETHAmount * 1e18) / price;
    }

    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return (_wstETHAmount * price) / 1e18;
    }
}
