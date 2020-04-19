pragma solidity ^0.5.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IVault.sol";


contract YToken is ERC20 {
    IERC20 public underlying;
    IVault public collateral; // Can be replaced for an EnumerableSet.AddressSet for multicollateralized yTokens
    uint256 public maturity;

    constructor(address underlying_, address collateral_, uint256 maturity_) public {
        underlying = IERC20(underlying_);
        collateral = IVault(collateral_);
        maturity = maturity_;
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
    function burn(uint256 amount) public returns (bool) {
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

    /// @dev Mint yTokens by locking its market value in collateral.
    function borrow(uint256 amount) public returns (bool) {
        // The vault will revert if there is not enough unlocked collateral
        collateral.lock(msg.sender, amount);
        _mint(msg.sender, amount);
        return true;
    }

    /// @dev Burn yTokens and unlock its market value in collateral.
    /// TODO: Does this make sense?
    function repay(uint256 amount) public returns (bool) {
        require(
            // solium-disable-next-line security/no-block-members
            now > maturity,
            "YToken: Wait for maturity"
        );
        _burn(msg.sender, amount);
        // The vault will revert if there is not enough locked collateral
        collateral.unlock(msg.sender, amount);
        return true;
    }
}
