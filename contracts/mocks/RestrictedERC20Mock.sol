// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/ERC20Permit.sol";
import "@yield-protocol/utils-v2/contracts/AccessControl.sol";

contract RestrictedERC20Mock is AccessControl(), ERC20Permit  {

    constructor(
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol) { }

    /// @dev Give tokens to whoever.
    function mint(address to, uint256 amount) public virtual auth {
        _mint(to, amount);
    }

    /// @dev Burn tokens from whoever.
    function burn(address from, uint256 amount) public virtual auth {
        _burn(from, amount);
    }
}
