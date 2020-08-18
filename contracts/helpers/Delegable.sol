// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


/// @dev Delegable enables users to delegate their account management to other users
contract Delegable {
    event Delegate(address indexed user, address indexed delegate, bool enabled);

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address user,address delegate,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x0000000000000000000000000000000;
    mapping(address => uint) public nonces;

    mapping(address => mapping(address => bool)) public delegated;

    constructor () public {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes('Yield')), // Can we get the name of the inheriting contract somehow?
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

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
        require(!delegated[msg.sender][delegate], "Delegable: Already delegated");
        delegated[msg.sender][delegate] = true;
        emit Delegate(msg.sender, delegate, true);
    }

    /// @dev Stop a delegate from acting on the behalf of caller
    function revokeDelegate(address delegate) public {
        require(delegated[msg.sender][delegate], "Delegable: Already undelegated");
        delegated[msg.sender][delegate] = false;
        emit Delegate(msg.sender, delegate, false);
    }

    /// @dev Add a delegate through a permit
    function permit(address user, address delegate, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'Yield: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, user, delegate, nonces[user]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == user, 'Yield: INVALID_SIGNATURE');
        delegated[user][delegate] = true;
    }
}