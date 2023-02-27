// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/esm/blob/master/src/ESM.sol
interface ESMAbstract {
    function gem() external view returns (address);
    function proxy() external view returns (address);
    function wards(address) external view returns (uint256);
    function sum(address) external view returns (address);
    function Sum() external view returns (uint256);
    function min() external view returns (uint256);
    function end() external view returns (address);
    function live() external view returns (uint256);
    function revokesGovernanceAccess() external view returns (bool);
    function rely(address) external;
    function deny(address) external;
    function file(bytes32, uint256) external;
    function file(bytes32, address) external;
    function cage() external;
    function fire() external;
    function denyProxy(address) external;
    function join(uint256) external;
    function burn() external;
}
