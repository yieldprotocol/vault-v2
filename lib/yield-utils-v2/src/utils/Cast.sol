// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

library Cast {
    ///@dev library for safe casting of value types

    function b12(bytes32 x) internal pure returns (bytes12 y) {
        require(bytes32(y = bytes12(x)) == x, "Cast overflow");
    }

    function b6(bytes32 x) internal pure returns (bytes6 y) {
        require(bytes32(y = bytes6(x)) == x, "Cast overflow");
    }

    function u256(int256 x) internal pure returns (uint256 y) {
        require(x >= 0, "Cast overflow");
        y = uint256(x);
    }

    function i256(uint256 x) internal pure returns (int256 y) {
        require(x <= uint256(type(int256).max), "Cast overflow");
        y = int256(x);
    }

    function u128(uint256 x) internal pure returns (uint128 y) {
        require(x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }

    function u128(int256 x) internal pure returns (uint128 y) {
        require(x >= 0, "Cast overflow");
        y = uint128(uint256(x));
    }

    function i128(uint256 x) internal pure returns (int128) {
        require(x <= uint256(int256(type(int128).max)), "Cast overflow");
        return int128(int256(x));
    }

    function i128(int256 x) internal pure returns (int128) {
        require(x <= type(int128).max, "Cast overflow");
        require(x >= type(int128).min, "Cast overflow");
        return int128(x);
    }

    function u112(uint256 x) internal pure returns (uint112 y) {
        require(x <= type(uint112).max, "Cast overflow");
        y = uint112(x);
    }

    function u104(uint256 x) internal pure returns (uint104 y) {
        require(x <= type(uint104).max, "Cast overflow");
        y = uint104(x);
    }

    function u32(uint256 x) internal pure returns (uint32 y) {
        require(x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }
}
