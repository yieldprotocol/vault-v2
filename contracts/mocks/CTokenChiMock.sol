// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./SourceMock.sol";


contract CTokenChiMock is SourceMock {
    uint public exchangeRateStored;

    function set(uint chi) external override {
        exchangeRateStored = chi;
    }

    function exchangeRateCurrent() public returns (uint) {
        return exchangeRateStored;
    }
}
