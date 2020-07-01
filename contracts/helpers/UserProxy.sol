pragma solidity ^0.6.2;


/// @dev UserProxy enables users to delegate their account management to proxies
contract UserProxy {
    // All proxies can be known from events for audit purposes
    event Proxy(address indexed user, address indexed proxy, bool enabled);

    mapping(address => mapping(address => bool)) internal proxies;

    /// @dev Require that tx.origin is the account holder or a proxy
    modifier onlyHolderOrProxy(address holder, string memory errorMessage) {
        require(
            msg.sender == holder || proxies[holder][msg.sender],
            errorMessage
        );
        _;
    }

    /// @dev Enable a proxy to act on the behalf of caller
    function addProxy(address proxy) public {
        proxies[msg.sender][proxy] = true;
        emit Proxy(msg.sender, proxy, true);
    }

    /// @dev Stop a proxy from acting on the behalf of caller
    function revokeProxy(address proxy) public {
        proxies[msg.sender][proxy] = false;
        emit Proxy(msg.sender, proxy, false);
    }
}