// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev The Migrations contract is a standard truffle contract that keeps track of which migrations were done on the current network.
 * For yDai, we have updated it and added functionality that enables it as well to work as a deployed contract registry.
 */
contract Migrations is Ownable() {
    uint public lastCompletedMigration;

    /// @dev Deployed contract to deployment address
    mapping(bytes32 => address) public contracts;

    /// @dev Contract name iterator
    bytes32[] public names;

    /// @dev Amount of registered contracts
    function length() external view returns (uint) {
        return names.length;
    }

    /// @dev Register a contract name and address
    function register(bytes32 name, address addr ) external onlyOwner {
        contracts[name] = addr;
        names.push(name);
    }

    /// @dev Register the index of the last completed migration
    function setCompleted(uint completed) public onlyOwner {
        lastCompletedMigration = completed;
    }

    /// @dev Copy the index of the last completed migration to a new version of the Migrations contract
    function upgrade(address newAddress) public onlyOwner {
        Migrations upgraded = Migrations(newAddress);
        upgraded.setCompleted(lastCompletedMigration);
    }
}
