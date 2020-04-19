pragma solidity ^0.5.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IOracle.sol";


contract Vault is Ownable { // TODO: Upgrade to openzeppelin 3.0 and use AccessControl
    using DecimalMath for uint256;

    event CollateralLocked(address collateral, address user, uint256 amount);
    event CollateralUnlocked(address collateral, address user, uint256 amount);

    // TODO: Use address(0) to represent Ether, consider also using an ERC20 Ether wrapper
    IERC20 internal collateral;
    IOracle internal oracle;
    mapping(address => uint256) internal posted;
    mapping(address => uint256) internal locked;

    constructor (address collateral_, address oracle_) public Ownable() {
        collateral = IERC20(collateral_);
        oracle = IOracle(oracle_);
    }

    /// @dev Return posted collateral of an user
    function postedOf(address user) public view returns (uint256) {
        // No need for SafeMath, can't lock more than you have.
        return posted[user];
    }

    /// @dev Return unlocked collateral of an user
    function unlockedOf(address user) public view returns (uint256) {
        // No need for SafeMath, can't lock more than you have.
        return posted[user] - locked[user];
    }

    /// @dev Post collateral
    /// TODO: Allow posting for others with AccessControl
    function post(uint256 amount) public returns (bool) {
        collateral.transferFrom(msg.sender, address(this), amount); // No need for extra events
        posted[msg.sender] += amount; // No need for SafeMath, can't overflow.
        return true;
    }

    /// @dev Retrieve collateral
    /// TODO: Allow retrieving for others with AccessControl
    function retrieve(uint256 amount) public returns (bool) {
        require(
            unlockedOf(msg.sender) >= amount,
            "Vault: Don't have it"
        );
        collateral.transfer(msg.sender, amount); // No need for extra events
        posted[msg.sender] -= amount; // No need for SafeMath, we are checking first.
        return true;
    }

    /// @dev Lock collateral equivalent to an amount of underlying
    /// TODO: Allow locking for others with AccessControl
    function lock(uint256 amount) public returns (bool) {
        uint256 collateralAmount = equivalentCollateral(amount);
        require(
            unlockedOf(msg.sender) >= collateralAmount,
            "Vault: Don't have it"
        );
        locked[msg.sender] += collateralAmount; // No need for SafeMath, can't overflow.
        emit CollateralLocked(address(collateral), msg.sender, collateralAmount);
        return true;
    }

    /// @dev Unlock collateral equivalent to an amount of underlying
    /// TODO: Allow unlocking for others with AccessControl
    function unlock(uint256 amount) public returns (bool) {
        uint256 collateralAmount = equivalentCollateral(amount);
        require(
            locked[msg.sender] >= collateralAmount,
            "Vault: Don't have it"
        );
        locked[msg.sender] -= collateralAmount; // No need for SafeMath, we are checking first.
        emit CollateralUnlocked(address(collateral), msg.sender, collateralAmount);
        return true;
    }

    function equivalentCollateral(uint256 amount) public view returns (uint256) {
        // TODO: Do I have to worry about the oracle returning zero?
        // TODO: What happens for tiny amounts that get divided to zero?
        return amount.divd(oracle.get(), 18); // TODO: Think about oracle decimals
    }
}
