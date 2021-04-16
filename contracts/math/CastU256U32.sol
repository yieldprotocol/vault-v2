// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;


library CastU256U32 {
    /// @dev Safely cast an uint256 to an u32
    function u32(uint256 x) internal pure returns (uint32 y) {
        require (x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }
}