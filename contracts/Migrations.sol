pragma solidity ^0.6.0;

contract Migrations {
    address public owner;
    uint public last_completed_migration;
    mapping(bytes32 => address) public contracts;

    constructor() public {
        owner = msg.sender;
    }

    modifier restricted() {
        if (msg.sender == owner) _;
    }

    function register(bytes32 name, address addr ) external restricted {
        contracts[name] = addr;
    }

    function setCompleted(uint completed) public restricted {
        last_completed_migration = completed;
    }

    function upgrade(address new_address) public restricted {
        Migrations upgraded = Migrations(new_address);
        upgraded.setCompleted(last_completed_migration);
    }
}
