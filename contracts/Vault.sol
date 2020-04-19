pragma solidity ^0.5.2;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol"; // Check line 20 of EnumerableSet :)


contract Vault is Ownable { // TODO: Upgrade to openzeppelin 3.0 and use AccessControl
    using EnumerableSet for EnumerableSet.AddressSet;

    event CollateralAccepted(address collateral);
    event CollateralLocked(address collateral, address user, uint256 amount);
    event CollateralUnlocked(address collateral, address user, uint256 amount);

    // TODO: Use address(0) to represent Ether, consider also using an ERC20 Ether wrapper
    EnumerableSet.AddressSet internal collaterals; // Set of accepted collateral contract addresses
    mapping(address => mapping(address => uint256)) internal posted;
    mapping(address => mapping(address => uint256)) internal locked;

    constructor () public Ownable() {}

    /// @dev Add a new accepted collateral contracts
    function accept(address collateral) public onlyOwner returns (bool) {
        require(
            collaterals.add(collateral) == true,
            "Vault: Already exists"
        );
        emit CollateralAccepted(collateral);
        return true;
    }

    /// @dev Return posted collateral of an user
    function postedOf(address collateral, address user) public view returns (uint256) {
        // No need for SafeMath, can't lock more than you have.
        return posted[collateral][user];
    }

    /// @dev Return unlocked collateral of an user
    function unlockedOf(address collateral, address user) public view returns (uint256) {
        // No need for SafeMath, can't lock more than you have.
        return posted[collateral][user] - locked[collateral][user];
    }

    /// @dev Post collateral of an accepted denomination
    /// TODO: Allow posting for others with AccessControl
    function post(address collateral, uint256 amount) public returns (bool) {
        require(
            collaterals.contains(collateral) == true,
            "Vault: Not accepted"
        );
        IERC20(collateral).transferFrom(msg.sender, address(this), amount); // No need for extra events
        posted[collateral][msg.sender] += amount; // No need for SafeMath, can't overflow.
        return true;
    }

    /// @dev Retrieve collateral
    /// TODO: Allow retrieving for others with AccessControl
    function retrieve(address collateral, uint256 amount) public returns (bool) {
        require(
            unlockedOf(collateral, msg.sender) >= amount,
            "Vault: Don't have it"
        );
        IERC20(collateral).transfer(msg.sender, amount); // No need for extra events
        posted[collateral][msg.sender] -= amount; // No need for SafeMath, we are checking first.
        return true;
    }

    /// @dev Lock collateral of an accepted denomination
    /// TODO: Allow locking for others with AccessControl
    function lock(address collateral, uint256 amount) public returns (bool) {
        require(
            unlockedOf(collateral, msg.sender) >= amount,
            "Vault: Don't have it"
        );
        locked[collateral][msg.sender] += amount; // No need for SafeMath, can't overflow.
        emit CollateralLocked(collateral, msg.sender, amount);
        return true;
    }

    /// @dev Unlock collateral
    /// TODO: Allow unlocking for others with AccessControl
    function unlock(address collateral, uint256 amount) public returns (bool) {
        require(
            locked[collateral][msg.sender] >= amount,
            "Vault: Don't have it"
        );
        locked[collateral][msg.sender] -= amount; // No need for SafeMath, we are checking first.
        emit CollateralUnlocked(collateral, msg.sender, amount);
        return true;
    }
}
