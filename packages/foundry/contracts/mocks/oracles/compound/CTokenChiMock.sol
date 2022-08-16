// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "../ISourceMock.sol";


contract CTokenChiMock is ISourceMock {
    uint public exchangeRateStored;

    function set(uint chi) external override {
        exchangeRateStored = chi;
    }

    function exchangeRateCurrent() public view returns (uint) {
        return exchangeRateStored;
    }

    function get(bytes32 base, bytes32 kind, uint256) external view returns (uint256 accumulator, uint256 updateTime)
    {
        accumulator = exchangeRateStored;
        updateTime = block.timestamp;
    }
}
