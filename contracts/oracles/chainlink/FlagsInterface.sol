// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/interfaces/FlagsInterface.sol
interface FlagsInterface {
  function getFlag(address) external view returns (bool);

  function getFlags(address[] calldata) external view returns (bool[] memory);

  function raiseFlag(address) external;

  function raiseFlags(address[] calldata) external;

  function lowerFlags(address[] calldata) external;

  function setRaisingAccessController(address) external;
}