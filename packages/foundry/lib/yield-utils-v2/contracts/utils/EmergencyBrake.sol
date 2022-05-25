// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../access/AccessControl.sol";


interface IEmergencyBrake {
    struct Permission {
        address contact;
        bytes4[] signatures;
    }

    function plan(address target, Permission[] calldata permissions) external returns (bytes32 txHash);
    function cancel(bytes32 txHash) external;
    function execute(bytes32 txHash) external;
    function restore(bytes32 txHash) external;
    function terminate(bytes32 txHash) external;
}

/// @dev EmergencyBrake allows to plan for and execute transactions that remove access permissions for a target
/// contract. In an permissioned environment this can be used for pausing components.
/// All contracts in scope of emergency plans must grant ROOT permissions to EmergencyBrake. To mitigate the risk
/// of governance capture, EmergencyBrake has very limited functionality, being able only to revoke existing roles
/// and to restore previously revoked roles. Thus EmergencyBrake cannot grant permissions that weren't there in the 
/// first place. As an additional safeguard, EmergencyBrake cannot revoke or grant ROOT roles.
/// In addition, there is a separation of concerns between the planner and the executor accounts, so that both of them
/// must be compromised simultaneously to execute non-approved emergency plans, and then only creating a denial of service.
contract EmergencyBrake is AccessControl, IEmergencyBrake {
    enum State {UNPLANNED, PLANNED, EXECUTED}

    struct Plan {
        State state;
        address target;
        bytes permissions;
    }

    event Planned(bytes32 indexed txHash, address indexed target);
    event Cancelled(bytes32 indexed txHash);
    event Executed(bytes32 indexed txHash, address indexed target);
    event Restored(bytes32 indexed txHash, address indexed target);
    event Terminated(bytes32 indexed txHash);

    mapping (bytes32 => Plan) public plans;

    constructor(address planner, address executor) AccessControl() {
        _grantRole(IEmergencyBrake.plan.selector, planner);
        _grantRole(IEmergencyBrake.cancel.selector, planner);
        _grantRole(IEmergencyBrake.execute.selector, executor);
        _grantRole(IEmergencyBrake.restore.selector, planner);
        _grantRole(IEmergencyBrake.terminate.selector, planner);

        // Granting roles (plan, cancel, execute, restore, terminate) is reserved to ROOT
    }

    /// @dev Compute the hash of a plan
    function hash(address target, Permission[] calldata permissions)
        external pure
        returns (bytes32 txHash)
    {
        txHash = keccak256(abi.encode(target, permissions));
    }

    /// @dev Register an access removal transaction
    function plan(address target, Permission[] calldata permissions)
        external override auth
        returns (bytes32 txHash)
    {
        txHash = keccak256(abi.encode(target, permissions));
        require(plans[txHash].state == State.UNPLANNED, "Emergency already planned for.");

        // Removing or granting ROOT permissions is out of bounds for EmergencyBrake
        for (uint256 i = 0; i < permissions.length; i++){
            for (uint256 j = 0; j < permissions[i].signatures.length; j++){
                require(
                    permissions[i].signatures[j] != ROOT,
                    "Can't remove ROOT"
                );
            }
        }

        plans[txHash] = Plan({
            state: State.PLANNED,
            target: target,
            permissions: abi.encode(permissions)
        });
        emit Planned(txHash, target);
    }

    /// @dev Erase a planned access removal transaction
    function cancel(bytes32 txHash)
        external override auth
    {
        require(plans[txHash].state == State.PLANNED, "Emergency not planned for.");
        delete plans[txHash];
        emit Cancelled(txHash);
    }

    /// @dev Execute an access removal transaction
    function execute(bytes32 txHash)
        external override auth
    {
        Plan memory plan_ = plans[txHash];
        require(plan_.state == State.PLANNED, "Emergency not planned for.");
        plans[txHash].state = State.EXECUTED;

        Permission[] memory permissions_ = abi.decode(plan_.permissions, (Permission[]));

        for (uint256 i = 0; i < permissions_.length; i++){
            // AccessControl.sol doesn't revert if revoking permissions that haven't been granted
            // If we don't check, planner and executor can collude to gain access to contacts
            Permission memory permission_ = permissions_[i]; 
            for (uint256 j = 0; j < permission_.signatures.length; j++){
                AccessControl contact = AccessControl(permission_.contact);
                bytes4 signature_ = permission_.signatures[j];
                require(
                    contact.hasRole(signature_, plan_.target),
                    "Permission not found"
                );
                contact.revokeRole(signature_, plan_.target);
            }
        }
        emit Executed(txHash, plan_.target);
    }

    /// @dev Restore the orchestration from an isolated target
    function restore(bytes32 txHash)
        external override auth
    {
        Plan memory plan_ = plans[txHash];
        require(plan_.state == State.EXECUTED, "Emergency plan not executed.");
        plans[txHash].state = State.PLANNED;

        Permission[] memory permissions_ = abi.decode(plan_.permissions, (Permission[]));

        for (uint256 i = 0; i < permissions_.length; i++){
            Permission memory permission_ = permissions_[i]; 
            for (uint256 j = 0; j < permission_.signatures.length; j++){
                AccessControl contact = AccessControl(permission_.contact);
                bytes4 signature_ = permission_.signatures[j];
                contact.grantRole(signature_, plan_.target);
            }
        }
        emit Restored(txHash, plan_.target);
    }

    /// @dev Remove the restoring option from an isolated target
    function terminate(bytes32 txHash)
        external override auth
    {
        require(plans[txHash].state == State.EXECUTED, "Emergency plan not executed.");
        delete plans[txHash];
        emit Terminated(txHash);
    }
}