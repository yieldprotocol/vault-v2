// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "../ISourceMock.sol";
import "./CTokenUnderlyingMock.sol";

contract CDaiMock is ISourceMock {
    uint public exchangeRateStored;
    address public underlying;

    constructor () {
        underlying = address(new CTokenUnderlyingMock(18));
    }

    function set(uint chi) external override {
        exchangeRateStored = chi;
    }

    function exchangeRateCurrent() public view returns (uint) {
        return exchangeRateStored;
    }
}
