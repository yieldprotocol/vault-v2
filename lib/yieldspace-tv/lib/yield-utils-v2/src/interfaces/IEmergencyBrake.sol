// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IEmergencyBrake {
    struct Plan {
        bool executed;
        mapping(bytes32 => Permission) permissions;
        bytes32[] ids;
    }

    struct Permission {
        address host;
        bytes4 signature;
    }

    function executed(address user) external view returns (bool);
    function contains(address user, Permission calldata permission) external view returns (bool);
    function permissionAt(address user, uint idx) external view returns (Permission memory);
    function index(address user, Permission calldata permission) external view returns (uint index_);

    function add(address user, Permission[] calldata permissionsIn) external;
    function remove(address user, Permission[] calldata permissionsOut) external;
    function cancel(address user) external;
    function check(address user) external view returns (bool);
    function execute(address user) external;
    function restore(address user) external;
    function terminate(address user) external;
}