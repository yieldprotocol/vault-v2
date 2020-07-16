// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


/// @dev Delegable enables users to delegate their account management to other users
contract Delegable {
    // All delegated can be known from events for audit purposes
    event Delegate(address indexed user, address indexed delegate, bool enabled);

    mapping(address => mapping(address => bool)) internal delegated;

    /// @dev Require that msg.sender is the account holder or a delegate
    modifier onlyHolderOrDelegate(address holder, string memory errorMessage) {
        require(
            msg.sender == holder || delegated[holder][msg.sender],
            errorMessage
        );
        _;
    }

    /// @dev Enable a delegate to act on the behalf of caller
    function addDelegate(address delegate) public {
        delegated[msg.sender][delegate] = true;
        emit Delegate(msg.sender, delegate, true);
    }

    /// @dev Stop a delegate from acting on the behalf of caller
    function revokeDelegate(address delegate) public {
        delegated[msg.sender][delegate] = false;
        emit Delegate(msg.sender, delegate, false);
    }
}