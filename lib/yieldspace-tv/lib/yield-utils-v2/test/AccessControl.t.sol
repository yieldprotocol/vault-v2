// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/token/IERC20.sol";
import { RestrictedERC20Mock } from "../src/mocks/RestrictedERC20Mock.sol";
import { TestExtensions } from "./utils/TestExtensions.sol";
import { TestConstants } from "./utils/TestConstants.sol";


using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions, TestConstants {

    event RoleAdminChanged(bytes4 indexed role, bytes4 indexed newAdminRole);
    event RoleGranted(bytes4 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes4 indexed role, address indexed account, address indexed sender);

    RestrictedERC20Mock public restricted;
    address owner;
    address other;
    bytes4 ROOT = 0x00000000;
    bytes4 LOCK = 0xFFFFFFFF;
    bytes4 role = RestrictedERC20Mock.mint.selector;
    bytes4 otherRole = RestrictedERC20Mock.burn.selector;
    bytes4[] roles;

    function setUpMock() public {
        owner = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;

        restricted = new RestrictedERC20Mock("Restricted", "RST");
    }

    function setUpHarness(string memory network) public {
        setUpMock(); // TODO: Think about a test harness.
    }

    function setUp() public virtual {
        string memory network = vm.envString(NETWORK);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envBool(MOCK)) setUpMock();
        else setUpHarness(network);

        //... Users ...
        other = address(2);
        vm.label(owner, "owner");
        vm.label(other, "other");
        vm.label(address(restricted), "restricted");

        roles.push(role);
        roles.push(otherRole);
    }
}

contract DeployedTest is Deployed {

    function testSetup() public {
        assertTrue(restricted.hasRole(ROOT, owner));
        assertFalse(restricted.hasRole(ROOT, other));
        assertFalse(restricted.hasRole(LOCK, owner));
        assertEq(restricted.getRoleAdmin(LOCK), LOCK);
    }

    function testAccessDenied() public {
        vm.expectRevert("Access denied");
        restricted.mint(other, 100);
    }

    function testOnlyAdminGrant() public {
        vm.expectRevert("Only admin");
        vm.prank(other);
        restricted.grantRole(role, other);
    }

    function testGrant() public {
        vm.expectEmit(true, true, true, false);
        emit RoleGranted(role, owner, owner);
        vm.startPrank(owner);
        restricted.grantRole(role, owner);
        assertTrue(restricted.hasRole(role, owner));

        restricted.mint(other, 100);
        vm.stopPrank();

        vm.expectRevert("Access denied");
        vm.prank(other);
        restricted.mint(other, 100);
    }

    function testGrantMultipleRoles() public {
        vm.expectEmit(true, true, true, false);
        emit RoleGranted(role, owner, owner);
        vm.expectEmit(true, true, true, false);
        emit RoleGranted(otherRole, owner, owner);
        vm.prank(owner);
        restricted.grantRoles(roles, owner);

        assertTrue(restricted.hasRole(role, owner));
        assertTrue(restricted.hasRole(otherRole, owner));
    }

    function testLock() public {
        vm.expectEmit(true, true, false, false);
        emit RoleAdminChanged(role, LOCK);
        vm.prank(owner);
        restricted.lockRole(role);

        assertEq(restricted.getRoleAdmin(role), LOCK);

        vm.expectRevert("Only admin");
        vm.prank(owner);
        restricted.grantRole(role, owner);
    }
}

abstract contract WithGrantedRoles is Deployed {
    function setUp() public override virtual {
        super.setUp();

        vm.prank(owner);
        restricted.grantRoles(roles, owner);
    }
}


contract WithGrantedRolesTest is WithGrantedRoles {

    function testRevokeRole() public {
        vm.expectEmit(true, true, true, false);
        emit RoleRevoked(role, owner, owner);
        vm.prank(owner);
        restricted.revokeRole(role, owner);

        assertFalse(restricted.hasRole(role, owner));
    }

    function testRevokeMultipleRoles() public {
        vm.expectEmit(true, true, true, false);
        emit RoleRevoked(role, owner, owner);
        vm.expectEmit(true, true, true, false);
        emit RoleRevoked(otherRole, owner, owner);
        vm.prank(owner);
        restricted.revokeRoles(roles, owner);

        assertFalse(restricted.hasRole(role, owner));
        assertFalse(restricted.hasRole(otherRole, owner));
    }
}