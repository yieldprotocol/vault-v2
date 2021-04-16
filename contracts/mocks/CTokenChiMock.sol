// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

contract CTokenChiMock {
    uint public exchangeRateStored;

    function set(uint chi) external {
        exchangeRateStored = chi;
    }

    function exchangeRateCurrent() public returns (uint) {
        return exchangeRateStored;
    }
}
