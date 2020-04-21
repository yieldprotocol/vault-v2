pragma solidity ^0.5.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IVault.sol";


contract YToken is ERC20 {
    IERC20 public underlying;
    mapping(address => uint256) internal debt; // In underlying
    IVault public collateral; // Can be replaced for an EnumerableSet.AddressSet for multicollateralized yTokens
    uint256 public maturity;

    constructor(address underlying_, address collateral_, uint256 maturity_) public {
        underlying = IERC20(underlying_);
        collateral = IVault(collateral_);
        maturity = maturity_;
    }

    /// @dev Return debt in underlying of an user
    function debtOf(address user) public view returns (uint256) {
        return debt[user];
    }

    /// @dev Mint yTokens by posting an equal amount of underlying.
    function mint(uint256 amount) public returns (bool) {
        require(
            underlying.transferFrom(msg.sender, address(this), amount) == true,
            "YToken: Failed transfer"
        );
        _mint(msg.sender, amount);
        return true;
    }

    /// @dev Burn yTokens and return an equal amount of underlying.
    function redeem(uint256 amount) public returns (bool) {
        require(
            // solium-disable-next-line security/no-block-members
            now > maturity,
            "YToken: Wait for maturity"
        );
        _burn(msg.sender, amount);
        require(
            underlying.transfer(msg.sender, amount) == true,
            "YToken: Failed transfer"
        );
        return true;
    }

    /// @dev Mint yTokens by locking its market value in collateral. Debt is recorded in the vault.
    function borrow(uint256 amount) public returns (bool) {
        debt[msg.sender] += amount; // Can't be higher than collateral.totalSupply(), can't overflow
        // The vault will revert if there is not enough unlocked collateral
        collateral.lock(msg.sender, debt[msg.sender]);
        _mint(msg.sender, amount);
        return true;
    }

    /// @dev Burn yTokens and unlock its market value in collateral. Debt is erased in the vault.
    function repay(uint256 amount) public returns (bool) {
        require(
            // solium-disable-next-line security/no-block-members
            debt[msg.sender] >= amount,
            "YToken: Not enough debt"
        );
        _burn(msg.sender, amount);
        debt[msg.sender] -= amount; // This can't underflow
        // The vault will revert if there is not enough locked collateral
        collateral.lock(msg.sender, debt[msg.sender]);
        return true;
    }
}
