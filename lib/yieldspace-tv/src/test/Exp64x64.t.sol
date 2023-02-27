// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;/*
  __     ___      _     _
  \ \   / (_)    | |   | | ████████╗███████╗███████╗████████╗███████╗
   \ \_/ / _  ___| | __| | ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    \   / | |/ _ \ |/ _` |    ██║   █████╗  ███████╗   ██║   ███████╗
     | |  | |  __/ | (_| |    ██║   ██╔══╝  ╚════██║   ██║   ╚════██║
     |_|  |_|\___|_|\__,_|    ██║   ███████╗███████║   ██║   ███████║
      yieldprotocol.com       ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚══════╝
*/
import "forge-std/Test.sol";

import "./helpers.sol";
import "./../YieldMath.sol";

/// @dev Tests for library: Exp64x64 (located in file YieldMath.sol)
contract Exp64x64Test is DSTest {
    /**TESTS*********************************************************

        Test name prefixe definitions:
        testUnit_          - Unit tests for common edge cases
        testFail_<reason>_ - Unit tests code reverts appropriately
        testFuzz_          - Property based fuzz tests
        NOTE: These functions are too complex for symbolic execution

    ****************************************************************/

    /* 1.  function pow(int256 x) internal pure returns (int128)
     ***************************************************************/

    function testUnit_pow_Exp64x64() public {
        uint128[7] memory xValues = [
            uint128(0x0),
            uint128(0x1000),
            uint128(0x2000),
            uint128(0x2000),
            uint128(0x2000),
            uint128(type(int128).max),
            uint128(type(uint128).max)
        ];
        uint128[7] memory yValues = [
            uint128(0x1000),
            uint128(0x1000),
            uint128(0x1000),
            uint128(0x0),
            uint128(0x1000),
            uint128(0x1000),
            uint128(0x1000)
        ];
        uint128[7] memory zValues = [
            uint128(0x1000),
            uint128(0x2000),
            uint128(0x2000),
            uint128(0x1000),
            uint128(0x10000),
            uint128(0x1000),
            uint128(0x2000)
        ];
        uint128 x;
        uint128 y;
        uint128 z;
        uint128 expectedResult;
        uint128 result;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            z = zValues[index];

            result = Exp64x64.pow(x, y, z);
            if (x == 0) {
                expectedResult = 0;
            } else {
                uint256 l = (uint256(
                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF - Exp64x64.log_2(x)
                ) * y) / z;
                if (l > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) expectedResult = 0;
                else
                    expectedResult = Exp64x64.pow_2(
                        uint128(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF - l)
                    );
            }
            assertEq(expectedResult, result);
        }
    }

    function testFail_ZisZero_pow_Exp64x64() public pure {
        Exp64x64.pow(uint128(0x1), uint128(0x1), uint128(0x0));
    }

    function testFail_XandYZero_pow_Exp64x64() public pure {
        Exp64x64.pow(uint128(0x0), uint128(0x0), uint128(0x1));
    }

    function testFuzz_pow_Exp64x64(
        uint256 passedInX,
        uint256 passedInY,
        uint256 passedInZ
    ) public {
        uint128 x = coerceUInt256To128(passedInX);
        uint128 y = coerceUInt256To128(passedInY);
        uint128 z = coerceUInt256To128(passedInZ);
        if (z == 0) z = 0x1;
        if (x == 0 && y == 0) y = 0x1;
        uint128 result = Exp64x64.pow(x, y, z);
        uint128 expectedResult;
        if (x == 0) {
            expectedResult = 0;
        } else {
            uint256 l = (uint256(
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF - Exp64x64.log_2(x)
            ) * y) / z;
            if (l > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) expectedResult = 0;
            else
                expectedResult = Exp64x64.pow_2(
                    uint128(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF - l)
                );
        }
        assertEq(expectedResult, result);
    }

    /* 2.  function log_2(uint128 x) internal pure returns (uint128)
     ***************************************************************/

    function testUnit_log_2_Exp64x64() public {
        uint128[5] memory xValues = [
            uint128(0x1),
            uint128(0x1000),
            uint128(0x2000),
            uint128(type(int128).max),
            uint128(type(uint128).max)
        ];
        uint128 x;
        uint128 expectedResult;
        uint128 result;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];

            result = Exp64x64.log_2(x);

            expectedResult = log2exp64x64(x);

            assertEq(expectedResult, result);
        }
    }

    function testFail_Zero_log_2_Exp64x64() public pure {
        Exp64x64.log_2(uint128(0x0));
    }

    function testFuzz_log_2_Exp64x64(uint128 x) public {
        if (x ==0) x = 0x1;

        uint128 result = Exp64x64.log_2(x);

        uint128 expectedResult = log2exp64x64(x);

        assertEq(expectedResult, result);
    }
    /* 3.  function pow_2(uint128 x) internal pure returns (uint128)
     ***************************************************************/

    function testUnit_pow_2_Exp64x64() public {
        uint128[5] memory xValues = [
            uint128(0x1),
            uint128(0x1000),
            uint128(0x2000),
            uint128(type(int128).max),
            uint128(type(uint128).max)
        ];
        uint128 x;
        uint128 expectedResult;
        uint128 result;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];

            result = Exp64x64.pow_2(x);

            expectedResult = pow2Exp64x64(x);

            assertEq(expectedResult, result);
        }
    }

    function testFuzz_pow_2_Exp64x64(uint256 passedInX) public {
        if (passedInX ==0) passedInX = 0x1;
        uint128 x = coerceUInt256To128(passedInX);

        uint128 result = Exp64x64.pow_2(x);

        uint128 expectedResult = pow2Exp64x64(x);

        assertEq(expectedResult, result);
    }
}
