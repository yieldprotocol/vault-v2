pragma solidity ^0.6.0;
import "@openzeppelin/contracts/access/Ownable.sol";


/// @dev Orchestrated allows to define static access control between multiple contracts
/// Think of it as a simple two tiered access control contract. It has an owner which can
/// execute functions with the `onlyOwner` modifier, and the owner can give access to other
/// addresses which then can execute functions with the `onlyOrchestrated` modifier.
contract Orchestrated is Ownable {
    event GrantedAccess(address access);

    mapping(address => bool) private authorized;

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
