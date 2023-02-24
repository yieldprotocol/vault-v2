// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/dss/blob/master/src/cure.sol
interface CureAbstract {
    function wards(address) external view returns (uint256);
    function live() external view returns (uint256);
    function srcs(uint256) external view returns (address);
    function wait() external view returns (uint256);
    function when() external view returns (uint256);
    function pos(address) external view returns (uint256);
    function amt(address) external view returns (uint256);
    function loadded(address) external view returns (uint256);
    function lCount() external view returns (uint256);
    function say() external view returns (uint256);
    function tCount() external view returns (uint256);
    function list() external view returns (address[] memory);
    function tell() external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function file(bytes32, uint256) external;
    function lift(address) external;
    function drop(address) external;
    function cage() external;
    function load(address) external;
}
