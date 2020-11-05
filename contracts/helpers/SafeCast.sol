pragma solidity ^0.6.10;

library SafeCast {
    /// @dev Safe casting from uint256 to uint128
    function toUint128(uint256 x) internal pure returns(uint128) {
        require(
            x <= type(uint128).max,
            "YieldProxy: Cast overflow"
        );
        return uint128(x);
    }

    /// @dev Safe casting from uint256 to int256
    function toInt256(uint256 x) internal pure returns(int256) {
        require(
            x <= uint256(type(int256).max),
            "YieldProxy: Cast overflow"
        );
        return int256(x);
    }
}