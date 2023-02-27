// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ERC20.sol";

contract ERC20Mock is ERC20 {

    constructor (string memory name, string memory symbol) ERC20(name, symbol) {}

    /// @dev Give free tokens to anyone
    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}