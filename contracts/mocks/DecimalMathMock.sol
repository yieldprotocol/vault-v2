// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;
import "../helpers/DecimalMath.sol";


/// @dev Implements simple fixed point math mul and div operations for 27 decimals.
contract DecimalMathMock is DecimalMath {

    function muld_(uint256 x, uint256 y) public pure returns (uint256) {
        return muld(x, y);
    }

    function divd_(uint256 x, uint256 y) public pure returns (uint256) {
        return divd(x, y);
    }

    function divdrup_(uint256 x, uint256 y) public pure returns (uint256)
    {
        return divdrup(x, y);
    }

    function muldrup_(uint256 x, uint256 y) public pure returns (uint256)
    {
        return muldrup(x, y);
    }
}
