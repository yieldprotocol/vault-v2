// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "../ISourceMock.sol";
import "../../ERC20Mock.sol";

contract WstETHMock is ISourceMock, ERC20Mock {
    uint256 public price;

    constructor () ERC20Mock("Wrapped liquid staked Ether 2.0", "wstETH") { }

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
