// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;


/// @dev Delegable enables users to delegate their account management to other users.
contract DelegableMock {
    mapping(address => mapping(address => bool)) public delegated;

    /// @dev Require that msg.sender is the account holder or a delegate
    modifier onlyHolderOrDelegate(address holder, string memory errorMessage) {
        require(
            msg.sender == holder || delegated[holder][msg.sender],
            errorMessage
        );
        _;
    }
}