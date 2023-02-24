// SPDX-License-Identifier: MIT
// Audit: https://hackmd.io/@devtooligan/YieldEmergencyBrakeSecurityReview2022-12-201

pragma solidity ^0.8.0;
import "../access/AccessControl.sol";
import "../interfaces/IEmergencyBrake.sol";


/// @dev EmergencyBrake allows to plan for and execute transactions that remove access permissions for a user
/// contract. In an permissioned environment this can be used for pausing components.
/// All contracts in scope of emergency plans must grant ROOT permissions to EmergencyBrake. To mitigate the risk
/// of governance capture, EmergencyBrake has very limited functionality, being able only to revoke existing roles
/// and to restore previously revoked roles. Thus EmergencyBrake cannot grant permissions that weren't there in the 
/// first place. As an additional safeguard, EmergencyBrake cannot revoke or grant ROOT roles.
contract EmergencyBrake is AccessControl, IEmergencyBrake {

    event Added(address indexed user, Permission permissionIn);
    event Removed(address indexed user, Permission permissionOut);
    event Executed(address indexed user);
    event Restored(address indexed user);

    uint256 public constant NOT_FOUND = type(uint256).max;

    mapping (address => Plan) public plans;

    constructor(address governor, address planner, address executor) AccessControl() {
        _grantRole(IEmergencyBrake.execute.selector, executor);
        _grantRole(IEmergencyBrake.add.selector, planner);
        _grantRole(IEmergencyBrake.remove.selector, planner);
        _grantRole(IEmergencyBrake.cancel.selector, planner);
        _grantRole(IEmergencyBrake.add.selector, governor);
        _grantRole(IEmergencyBrake.remove.selector, governor);
        _grantRole(IEmergencyBrake.cancel.selector, governor);
        _grantRole(IEmergencyBrake.execute.selector, governor);
        _grantRole(IEmergencyBrake.restore.selector, governor);
        _grantRole(IEmergencyBrake.terminate.selector, governor);
        // Granting roles (add, remove, cancel, execute, restore, terminate) is reserved to ROOT
    }

    /// @dev Is a plan executed?
    /// @param user address with auth privileges on permission hosts
    function executed(address user) external view override returns (bool) {
        return plans[user].executed;
    }

    /// @dev Does a plan contain a permission?
    /// @param user address with auth privileges on permission hosts
    /// @param permission permission that is being queried about
    function contains(address user, Permission calldata permission) external view override returns (bool) {
        return plans[user].permissions[_permissionToId(permission)].signature != bytes4(0);
    }

    /// @dev Return a permission by index
    /// @param user address with auth privileges on permission hosts
    /// @param idx permission index that is being queried about
    function permissionAt(address user, uint idx) external view override returns (Permission memory) {
        Plan storage plan_ = plans[user];
        return plan_.permissions[plan_.ids[idx]];
    }

    /// @dev Index of a permission in a plan. Returns type(uint256).max if not present.
    /// @param user address with auth privileges on permission hosts
    /// @param permission permission that is being queried about
    function index(address user, Permission calldata permission) external view override returns (uint) {
        Plan storage plan_ = plans[user];
        uint length = uint(plan_.ids.length);

        bytes32 id = _permissionToId(permission);

        for (uint i = 0; i < length; ++i ) {
            if (plan_.ids[i] == id) {
                return i;
            }
        }
        return NOT_FOUND;
    }

    /// @dev Number of permissions in a plan
    /// @param user address with auth privileges on permission hosts
    function total(address user) external view returns (uint) {
        return uint(plans[user].ids.length);
    }

    /// @dev Add permissions to an isolation plan
    /// @param user address with auth privileges on permission hosts
    /// @param permissionsIn permissions that are being added to an existing plan
    function add(address user, Permission[] calldata permissionsIn)
        external override auth 
    {   
        Plan storage plan_ = plans[user];
        require(!plan_.executed, "Plan in execution");

        uint length = permissionsIn.length;
        for (uint i; i < length; ++i) {
            Permission memory permissionIn = permissionsIn[i];
            require(permissionIn.signature != ROOT, "Can't remove ROOT");

            require(
                AccessControl(permissionIn.host).hasRole(permissionIn.signature, user),
                "Permission not found"
            ); // You don't want to find out execute reverts when you need it

            require(
                AccessControl(permissionIn.host).hasRole(ROOT, address(this)),
                "Need ROOT on host"
            ); // You don't want to find out you don't have ROOT while executing

            bytes32 idIn = _permissionToId(permissionIn);
            require(plan_.permissions[idIn].signature == bytes4(0), "Permission already set");

            plan_.permissions[idIn] = permissionIn; // Set the permission
            plan_.ids.push(idIn);

            emit Added(user, permissionIn);
        }

    }

    /// @dev Remove permissions from an isolation plan
    /// @param user address with auth privileges on permission hosts
    /// @param permissionsOut permissions that are being removed from an existing plan
    function remove(address user, Permission[] calldata permissionsOut) 
        external override auth
    {   
        Plan storage plan_ = plans[user];
        require(!plan_.executed, "Plan in execution");

        uint length = permissionsOut.length;
        for (uint i; i < length; ++i) {
            Permission memory permissionOut = permissionsOut[i];
            bytes32 idOut = _permissionToId(permissionOut);
            require(plan_.permissions[idOut].signature != bytes4(0), "Permission not found");

            delete plan_.permissions[idOut]; // Remove the permission
            
            // Loop through the ids array, copy the last item on top of the removed permission, then pop.
            uint last = uint(plan_.ids.length) - 1; // Length should be at least one at this point.
            for (uint j = 0; j <= last; ++j ) {
                if (plan_.ids[j] == idOut) {
                    if (j != last) plan_.ids[j] = plan_.ids[last];
                    plan_.ids.pop(); // Remove the id
                    break;
                }
            }

            emit Removed(user, permissionOut);
        }
    }

    /// @dev Remove a planned isolation plan
    /// @param user address with an isolation plan
    function cancel(address user)
        external override auth
    {
        Plan storage plan_ = plans[user];
        require(plan_.ids.length > 0, "Plan not found");
        require(!plan_.executed, "Plan in execution");

        _erase(user);
    }

    /// @dev Remove the restoring option from an isolated user
    /// @param user address with an isolation plan
    function terminate(address user)
        external override auth
    {
        Plan storage plan_ = plans[user];
        require(plan_.executed, "Plan not in execution");
        // If the plan is executed, then it must exist
        _erase(user);
    }

    /// @dev Remove all data related to an user
    /// @param user address with an isolation plan
    function _erase(address user)
        internal
    {
        Plan storage plan_ = plans[user];

        // Loop through the plan, and remove permissions and ids.
        uint length = uint(plan_.ids.length);

        // First remove the permissions
        for (uint i = length; i > 0; --i ) {
            bytes32 id = plan_.ids[i - 1];
            emit Removed(user, plan_.permissions[id]);
            delete plan_.permissions[id];
            plan_.ids.pop();
        }

        delete plans[user];
    }


    /// @dev Check if a plan is valid for execution
    /// @param user address with an isolation plan
    function check(address user)
        external view override returns (bool)
    {
        Plan storage plan_ = plans[user];

        // Loop through the ids array, and check all roles.
        uint length = uint(plan_.ids.length);
        require(length > 0, "Plan not found");

        for (uint i = 0; i < length; ++i ) {
            bytes32 id = plan_.ids[i];
            Permission memory permission_ = plan_.permissions[id]; 
            AccessControl host = AccessControl(permission_.host);

            if (!host.hasRole(permission_.signature, user)) return false;
        }

        return true;
    }

    /// @dev Execute an access removal transaction
    /// @notice The plan needs to be kept up to date with the current permissioning, or it will revert.
    /// @param user address with an isolation plan
    function execute(address user)
        external override auth
    {
        Plan storage plan_ = plans[user];
        require(!plan_.executed, "Already executed");
        plan_.executed = true;

        // Loop through the ids array, and revoke all roles.
        uint length = uint(plan_.ids.length);
        require(length > 0, "Plan not found");

        for (uint i = 0; i < length; ++i ) {
            bytes32 id = plan_.ids[i];
            Permission memory permission_ = plan_.permissions[id]; 
            AccessControl host = AccessControl(permission_.host);

            // `revokeRole` won't revert if the role is not granted, but we need
            // to revert because otherwise operators with `execute` and `restore`
            // permissions will be able to restore removed roles if the plan is not
            // updated to reflect the removed roles.
            // By reverting, a plan that is not up to date will revert on execution,
            // but that seems like a lesser evil versus allowing operators to override
            // governance decisions.
            require(
                host.hasRole(permission_.signature, user),
                "Permission not found"
            );
            host.revokeRole(permission_.signature, user);
        }

        emit Executed(user);
    }

    /// @dev Restore the orchestration from an isolated user
    function restore(address user)
        external override auth
    {
        Plan storage plan_ = plans[user];
        require(plan_.executed, "Plan not executed");
        plan_.executed = false;

        // Loop through the ids array, and grant all roles.
        uint length = uint(plan_.ids.length);

        for (uint i = 0; i < length; ++i ) {
            bytes32 id = plan_.ids[i];
            Permission memory permission_ = plan_.permissions[id]; 
            AccessControl host = AccessControl(permission_.host);
            bytes4 signature_ = permission_.signature;
            host.grantRole(signature_, user);
        }

        emit Restored(user);
    }


    /// @dev used to calculate the id of a Permission so it can be indexed within a Plan
    /// @param permission a permission, containing a host address and a function signature
    function permissionToId(Permission calldata permission)
        external pure returns(bytes32 id)
    {
        id = _permissionToId(permission);
    }

    /// @dev used to recreate a Permission from it's id
    /// @param id the key used for indexing a Permission within a Plan
    function idToPermission(bytes32 id)
        external pure returns(Permission memory permission) 
    {
        permission = _idToPermission(id);
    }

    function _permissionToId(Permission memory permission) 
        internal pure returns(bytes32 id) 
    {
        id = bytes32(abi.encodePacked(permission.signature, permission.host));
    }

    function _idToPermission(bytes32 id) 
        internal pure returns(Permission memory permission)
    {
        address host = address(bytes20(id));
        bytes4 signature = bytes4(id << 160);
        permission = Permission(host, signature);
    }
}
