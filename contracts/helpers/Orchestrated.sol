// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @dev Orchestrated allows to define static access control between multiple contracts.
 * This contract would be used as a parent contract of any contract that needs to restrict access to some methods,
 * which would be marked with the `onlyOrchestrated modifier.
 * During deployment, the contract deployer (`owner`) can register any contracts that have privileged access by calling `orchestrate`.
 * Once deployment is completed, `owner` can call `transferOwnership(address(0))` to avoid any more contracts ever gaining privileged access.
 */

contract Orchestrated is Ownable {
    event GrantedAccess(address access);

    mapping(address => bool) public authorized;

    constructor () public Ownable() {}

    /// @dev Restrict usage to authorized users
    modifier onlyOrchestrated(string memory err) {
        require(authorized[msg.sender], err);
        _;
    }

    /// @dev Add user to the authorized users list
    function orchestrate(address user) public onlyOwner {
        authorized[user] = true;
        emit GrantedAccess(user);
    }
}
