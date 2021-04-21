// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;
import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";


contract USDCMock is ERC20Permit {

    constructor() ERC20Permit("USD Coin", "USDC", 6) { }

    function version() public pure override returns(string memory) { return "2"; }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
