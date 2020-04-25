pragma solidity ^0.5.2;


interface IVault {
    event CollateralLocked(address collateral, address user, uint256 amount);
    event CollateralUnlocked(address collateral, address user, uint256 amount);

    /// @dev Return posted collateral of an user
    function balanceOf(address user) external view returns (uint256);

    /// @dev Return unlocked collateral of an user
    function unlockedOf(address user) external view returns (uint256);

    /// @dev Post collateral
    /// TODO: Allow posting for others with AccessControl
    function post(uint256 amount) external returns (bool);

    /// @dev Retrieve collateral
    /// TODO: Allow retrieving for others with AccessControl
    function withdraw(uint256 amount) external returns (bool);

    /// @dev Lock collateral equivalent to an amount of underlying
    /// TODO: Allow locking for others with AccessControl
    function lock(address user, uint256 amount) external returns (bool);

    /// @dev Unlock collateral equivalent to an amount of underlying
    /// TODO: Allow unlocking for others with AccessControl
    function unlock(address user, uint256 amount) external returns (bool);

    function equivalentCollateral(uint256 amount) external view returns (uint256);
}
