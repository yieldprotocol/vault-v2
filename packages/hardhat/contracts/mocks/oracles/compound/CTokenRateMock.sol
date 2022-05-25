// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "../ISourceMock.sol";


contract CTokenRateMock is ISourceMock {
    uint public borrowIndex;

    function set(uint rate) external override {
        borrowIndex = rate;
    }
}
