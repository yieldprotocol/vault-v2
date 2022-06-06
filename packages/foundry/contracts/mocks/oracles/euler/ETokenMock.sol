// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import {IEToken} from "../../../oracles/euler/IEToken.sol";

contract ETokenMock is IEToken {
    uint256 public balanceToUnderlyingResult = 0xdead;
    uint256 public underlyingToBalanceResult = 0xbeef;

    function convertBalanceToUnderlying(uint256 balance) external view returns (uint256) {
        return balanceToUnderlyingResult;
    }

    function convertUnderlyingToBalance(uint256 underlyingAmount) external view returns (uint256) {
        return underlyingToBalanceResult;
    }
}
