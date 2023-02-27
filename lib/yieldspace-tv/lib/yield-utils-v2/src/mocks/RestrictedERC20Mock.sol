// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../token/ERC20Permit.sol";
import "../access/AccessControl.sol";

contract RestrictedERC20Mock is AccessControl(), ERC20Permit  {

    constructor(
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol, 18) { }

    /// @dev Give tokens to whoever.
    function mint(address to, uint256 amount) public virtual auth {
        _mint(to, amount);
    }

    /// @dev Burn tokens from whoever.
    function burn(address from, uint256 amount) public virtual auth {
        _burn(from, amount);
    }

    // Uncomment this function to see collision protection for ROOT
    /* function ROOT12007226833() public view {
        console.logBytes4(msg.sig);
    } */

    // Uncomment this function to see collision protection for LOCK
    /* function LOCK10462387368() public view {
        console.logBytes4(msg.sig);
    } */
}
