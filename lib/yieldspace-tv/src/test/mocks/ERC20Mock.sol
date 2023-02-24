// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

import "@yield-protocol/utils-v2/src/token/ERC20.sol";


abstract contract Mintable is ERC20 {
    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

contract ERC20Mock is Mintable {
  constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) {}
}