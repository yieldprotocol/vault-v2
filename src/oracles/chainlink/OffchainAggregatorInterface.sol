// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface OffchainAggregatorInterface {

    function minAnswer() external view returns (int192);
    function maxAnswer() external view returns (int192);
}
