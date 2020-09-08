// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../helpers/DecimalMath.sol";


/// @dev Implements simple fixed point math mul and div operations for 27 decimals.
contract DecimalMathInvariant is DecimalMath {
    constructor () public {
    }

    function muld_(uint256 x, uint256 y) public pure returns (uint256) {
        uint z = muld(x, y);
        assert((x * y) / UNIT == z); // Assert math
        assert (divd(z, y) <= x);    // We are rounding down
        // Assert revert on overflow
        if(y > UNIT) assert(z >= x); // x could be zero
        if(y < UNIT) assert(z <= x); // y could be zero
    }

    function divd_(uint256 x, uint256 y) public pure returns (uint256) {
        uint z = divd(x, y);
        assert((x * UNIT) / y == z); // Assert math
        assert (muld(z, y) <= x);    // We are rounding down
        // Assert revert on overflow
        if(y > UNIT) assert(z <= x); // x could be zero
        if(y < UNIT) assert(z >= x); // x or y could be zero
    }

    function divdrup_(uint256 x, uint256 y) public pure returns (uint256) {
        uint z = divdrup(x, y);

        assert (muld(z, y) >= x); // We are rounding up
        if (muld(z, y) > x) assert (divd(x, y) == z - 1); // Unless z * y is exactly x, we have rounded up.

        if(y > UNIT) assert(z <= x); // x could be zero
        if(y < UNIT) assert(z >= x); // x or y could be zero
    }

    function muldrup_(uint256 x, uint256 y) public pure returns (uint256) {
        uint z = muldrup(x, y);
        
        assert (divd(z, y) >= x); // We are rounding up
        if (divd(z, y) > x) assert (muld(x, y) == z - 1);  // Unless z / y is exactly x, we have rounded up.

        if(y > UNIT) assert(z >= x); // x could be zero
        if(y < UNIT) assert(z <= x); // x or y could be zero
    }
}
