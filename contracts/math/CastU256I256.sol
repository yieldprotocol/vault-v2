// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;


library CastU256I256 {
    /// @dev Safely cast an uint256 to an int256
    function i256(uint256 x) internal pure returns (int256 y) {
        require (x <= uint256(type(int256).max), "Cast overflow");
        y = int256(x);
    }
}