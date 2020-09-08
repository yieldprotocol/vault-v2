// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "@openzeppelin/contracts/math/SafeMath.sol";


/// @dev Implements simple fixed point math mul and div operations for 27 decimals.
contract DecimalMath {
    using SafeMath for uint256;

    uint256 constant public UNIT = 1e27;

    /// @dev Multiplies x and y, assuming they are both fixed point with 27 digits.
    function muld(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mul(y).div(UNIT);
    }

    /// @dev Divides x between y, assuming they are both fixed point with 27 digits.
    function divd(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mul(UNIT).div(y);
    }

    /// @dev Multiplies x and y, rounding up to the closest representable number.
    /// Assumes x and y are both fixed point with `decimals` digits.
    function muldrup(uint256 x, uint256 y) internal pure returns (uint256)
    {
        uint256 z = x.mul(y);
        return z.mod(UNIT) == 0 ? z.div(UNIT) : z.div(UNIT).add(1);
    }

    /// @dev Divides x between y, rounding up to the closest representable number.
    /// Assumes x and y are both fixed point with `decimals` digits.
    function divdrup(uint256 x, uint256 y) internal pure returns (uint256)
    {
        uint256 z = x.mul(UNIT);
        return z.mod(y) == 0 ? z.div(y) : z.div(y).add(1);
    }
}
