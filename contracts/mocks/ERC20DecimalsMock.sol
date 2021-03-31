// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/ERC20Permit.sol";


contract ERC20DecimalsMock is ERC20Permit  {

    constructor(
        string memory name,
        string memory symbol,
        uint256 decimals_
    ) ERC20Permit(name, symbol) {
        decimals = decimals_;
    }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
