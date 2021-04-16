// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;


library WDivUp { // Fixed point arithmetic in 18 decimal units
    // Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds up.
    function wdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * 1e18 + y;
        unchecked { z -= 1; }
        z /= y;
    }
}