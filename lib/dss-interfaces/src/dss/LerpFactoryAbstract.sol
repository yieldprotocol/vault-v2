// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/dss-lerp/blob/master/src/LerpFactory.sol
interface LerpFactoryAbstract {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function lerps(bytes32) external view returns (address);
    function active(uint256) external view returns (address);
    function newLerp(bytes32, address, bytes32, uint256, uint256, uint256, uint256) external returns (address);
    function newIlkLerp(bytes32, address, bytes32, bytes32, uint256, uint256, uint256, uint256) external returns (address);
    function tall() external;
    function count() external view returns (uint256);
    function list() external view returns (address[] memory);
}
