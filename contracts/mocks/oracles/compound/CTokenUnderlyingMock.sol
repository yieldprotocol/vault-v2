// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;


contract CTokenUnderlyingMock {
    uint8 public decimals;

    constructor (uint8 decimals_) {
        decimals = decimals_;
    }
}
