pragma solidity ^0.6.0;
import "@openzeppelin/contracts/math/SafeMath.sol";


/// @dev Implements simple fixed point math mul and div operations.
/// @author Alberto Cuesta Cañada
contract DecimalMath {
    using SafeMath for uint256;

    uint256 constant public UNIT = 1000000000000000000000000000;

    /// @dev Multiplies x and y, assuming they are both fixed point with 27 digits.
    function muld(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mul(y).div(UNIT);
    }

    /// @dev Divides x between y, assuming they are both fixed point with 18 digits.
    function divd(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mul(UNIT).div(y);
    }
}
