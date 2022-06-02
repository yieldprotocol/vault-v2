// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;


library CastU128U104 {
    /// @dev Safely cast an uint128 to an uint104
    function u104(uint128 x) internal pure returns (uint104 y) {
        require (x <= type(uint104).max, "Cast overflow");
        y = uint104(x);
    }
}