// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;


contract OffchainAggregatorMock {
    int128 public minAnswer;
    int128 public maxAnswer;

    constructor() {
        minAnswer = 0;
        maxAnswer = type(int128).max;
    }

    function setLimits(int128 minAnswer_, int128 maxAnswer_) external {
        minAnswer = minAnswer_;
        maxAnswer = maxAnswer_;
    }
}