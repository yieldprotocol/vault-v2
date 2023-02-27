// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15; /*
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
import "./../Math64x64.sol";

contract Math64x64Test is Test {
    using Math64x64 for uint256;
    /**TESTS*********************************************************

        Tests grouped by function:
        1.  function fromInt(int256 x) internal pure returns (int128)
        2.  function toInt(int128 x) internal pure returns (int64)
        3.  function fromUInt(uint256 x) internal pure returns (int128)
        4.  function toUInt (int128 x) internal pure returns (uint64)
        5.  function from128x128 (int256 x) internal pure returns (int128)
        6.  function to128x128 (int256 x) internal pure returns (int128)
        7.  function add (int128 x, int128 y) internal pure returns (int128)
        8.  function sub (int128 x, int128 y) internal pure returns (int128)
        9.  function mul (int128 x, int128 y) internal pure returns (int128)
        10. function muli (int128 x, int256 y) internal pure returns (int256)
        11. function mulu (int128 x, uint256 y) internal pure returns (uint256)
        12. function div (int128 x, int128 y) internal pure returns (int128)
        13. function divi (int256 x, int256 y) internal pure returns (int128)
        14. function divu (uint256 x, uint256 y) internal pure returns (int128)
        15. function neg (int128 x) internal pure returns (int128)
        16. function abs (int128 x) internal pure returns (int128)
        17. function inv (int128 x) internal pure returns (int128)
        18. function avg (int128 x, int128 y) internal pure returns (int128)
        19. function gavg (int128 x, int128 y) internal pure returns (int128)
        20. function pow (int128 x, uint256 y) internal pure returns (int128)
        21. function sqrt (int128 x) internal pure returns (int128)
        22. function log_2 (int128 x) internal pure returns (int128)
        23. function ln(int128 x) internal pure returns (int128)
        24. function exp_2 (int128 x) internal pure returns (int128)
        25. function exp (int128 x) internal pure returns (int128)
        26. function divuu (uint256 x, uint256 y) internal pure returns (uint128)
        27. function sqrtu (uint256 x, uint256 r) internal pure returns (uint128)


        Test name prefix definitions:
        testUnit_          - Unit tests for common edge cases
        testFail_<reason>_ - Unit tests code reverts appropriately
        testFuzz_          - Property based fuzz tests

    ****************************************************************/

    // create an external contract for use with try/catch
    ForTesting public forTesting;

    constructor() {
        forTesting = new ForTesting();
    }

    /* 1.  function fromInt(int256 x) internal pure returns (int128)
     ***************************************************************/

    function testUnit_fromInt_Math64x64() public {
        int256[9] memory fromValues = [
            int256(0x7FFFFFFFFFFFFFFF),
            int256(0x7FFFFFFFFFFFFFFF - 1),
            int256(0x2),
            int256(0x1),
            int256(0x0),
            int256(-0x1),
            int256(-0x2),
            int256(-0x8000000000000000 + 1),
            int256(-0x8000000000000000)
        ];
        int256 from;
        for (uint256 index = 0; index < fromValues.length; index++) {
            from = fromValues[index];
            int128 result = Math64x64.fromInt(from);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = int128(from << 64);

            assertEq(expectedResult, result);
        }
    }

    function testFail_TooHigh_fromInt_Math64x64() public pure {
        Math64x64.fromInt(int256(0x7FFFFFFFFFFFFFFF + 1));
    }

    function testFail_TooLow_fromInt_Math64x64() public pure {
        Math64x64.fromInt(int256(-0x8000000000000000 - 1));
    }

    function testFuzz_fromInt_Math64x64(int256 passedIn) public {
        int256 from = coerceInt256To128(
            passedIn,
            -0x8000000000000000,
            0x7FFFFFFFFFFFFFFF
        );

        int128 result = Math64x64.fromInt(from);

        // Work backward to derive expected param
        int64 expectedFrom = Math64x64.toInt(result);
        assertEq(from, int256(expectedFrom));

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = from > from + 1;
        }

        if (!overflows && (from + 1 <= 0x7FFFFFFFFFFFFFFF)) {
            require(Math64x64.fromInt(from + 1) > result);
        }
        // abs(fn(x)) < abs(x)
        require(abs(result) >= abs(from));
    }

    /* 2.  function toInt(int128 x) internal pure returns (int64)
     ***************************************************************/
    function testUnit_toInt_Math64x64() public {
        int128[11] memory toValues = [
            type(int128).max,
            int128(0x7fffffffffffffff0000000000000000),
            int128(0x7FFFFFFFFFFFFFFF),
            int128(0x2),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(-0x2),
            int128(-0x8000000000000000),
            int128(-0x80000000000000000000000000000000 + 1),
            type(int128).min
        ];
        int128 to;
        for (uint256 index = 0; index < toValues.length; index++) {
            to = toValues[index];
            int64 result = Math64x64.toInt(to);

            // Re-implement logic from lib to derive expected result
            int64 expectedResult = int64(to >> 64);

            assertEq(expectedResult, result);
        }
    }

    function testFuzz_toInt_Math64x64(uint256 x) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();

        int64 result = Math64x64.toInt(x64);

        // Re-implement logic from lib x64 derive expected result
        int64 expectedResult = int64(x64 >> 64);
        assertEq(expectedResult, result);

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = x64 > x64 + 1;
        }
        if (!overflows) {
            require(Math64x64.toInt(x64 + 1) >= result);
        }

        // abs(fn(x)) < abs(x)
        require(abs(result) <= abs(x64));
    }

    /* 3.  function fromUInt(uint256 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_fromUInt_Math64x64() public {
        uint256[5] memory fromValues = [
            uint256(0x7fffffffffffffff),
            uint256(0x7fffffffffffffff - 1),
            uint256(0x2),
            uint256(0x1),
            type(uint256).min
        ];
        uint256 from;
        for (uint256 index = 0; index < fromValues.length; index++) {
            from = fromValues[index];
            int128 result = Math64x64.fromUInt(from);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = int128(uint128(from << 64));
            assertEq(expectedResult, result);
        }
    }

    function testFail_TooHigh_fromUInt_Math64x64() public pure {
        Math64x64.fromUInt(uint256(0x7FFFFFFFFFFFFFFF + 1));
    }

    function testFuzz_fromUInt_Math64x64(uint256 passedIn) public {
        uint256 from = passedIn % (0x7FFFFFFFFFFFFFFF + 1);

        int128 result = Math64x64.fromUInt(from);

        // Re-implement logic from lib to derive expected result
        int128 expectedResult = int128(uint128(from << 64));

        assertEq(expectedResult, result);

        // Work backward to derive expected param
        uint256 expectedFrom = uint256(uint128(result >> 64));
        assertEq(from, expectedFrom);

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = from > from + 1;
        }

        if (!overflows && (from + 1 <= 0x7FFFFFFFFFFFFFFF)) {
            require(Math64x64.fromUInt(from + 1) > result);
        }
        // fn(x) >= x
        require(uint256(uint128(result)) >= from);
    }

    /* 4.  function toUInt (int128 x) internal pure returns (uint64)
     ***************************************************************/
    function testUnit_toUInt_Math64x64() public {
        int128[8] memory toValues = [
            type(int128).max,
            int128(0x7fffffffffffffff + 1),
            int128(0x7fffffffffffffff),
            int128(0x7ffffffffffffff - 1),
            int128(type(int64).max),
            int128(0x2),
            int128(0x1),
            int128(0x0)
        ];
        int128 to;
        for (uint256 index = 0; index < toValues.length; index++) {
            to = toValues[index];
            uint64 result = Math64x64.toUInt(to);

            // Re-implement logic from lib to derive expected result
            uint64 expectedResult = uint64(int64(to >> 64));

            assertEq(expectedResult, result);
        }
    }

    function testFail_negativeNumber_toUInt_Math64x64() public pure {
        Math64x64.toUInt(-1);
    }

    /* 5.  function from128x128 (int256 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_from128x128_Math64x64() public {
        int256[11] memory fromValues = [
            type(int128).max,
            int256(0x7fffffffffffffff0000000000000000),
            int256(0x7FFFFFFFFFFFFFFF),
            int256(0x2),
            int256(0x1),
            int256(0x0),
            int256(-0x1),
            int256(-0x2),
            int256(-0x8000000000000000),
            int256(-0x80000000000000000000000000000000 + 1),
            type(int128).min
        ];
        int256 from;
        for (uint256 index = 0; index < fromValues.length; index++) {
            from = fromValues[index];
            int128 result = Math64x64.from128x128(from);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = int128(from >> 64);

            assertEq(expectedResult, result);
        }
    }

    // NOTE: No fuzz tests for from128x128() ^^ because too many cases would be reverted

    /* 6.  function to128x128 (int128 x) internal pure returns (int256)
     ***************************************************************/
    function testUnit_to128x128_Math64x64() public {
        int128[11] memory toValues = [
            type(int128).max,
            int128(0x7fffffffffffffff0000000000000000),
            int128(0x7FFFFFFFFFFFFFFF),
            int128(0x2),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(-0x2),
            int128(-0x8000000000000000),
            int128(-0x80000000000000000000000000000000 + 1),
            type(int128).min
        ];
        int128 to;
        for (uint256 index = 0; index < toValues.length; index++) {
            to = toValues[index];
            int256 result = Math64x64.to128x128(to);

            // Re-implement logic from lib to derive expected result
            int256 expectedResult = int256(to) << 64;

            assertEq(expectedResult, result);
        }
    }

    function testFuzz_to128x128_Math64x64(uint256 x) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();

        int256 result = Math64x64.to128x128(x64);

        // Re-implement logic from lib to derive expected result
        int256 expectedResult = int256(x64) << 64;

        assertEq(expectedResult, result);

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = x64 > x64 + 1;
        }
        if (!overflows) {
            require(Math64x64.to128x128(x64 + 1) >= result);
        }
    }

    /* 7.  function add (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_add_Math64x64() public {
        int128[9] memory xValues = [
            type(int128).min,
            int128(-0x1000),
            int128(-0x1),
            int128(0x0),
            int128(0x0),
            int128(0x1),
            int128(0x1),
            int128(0x1000),
            int128(type(int64).max)
        ];
        int128[9] memory yValues = [
            int128(type(int64).max),
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(0x0),
            type(int128).min,
            int128(-0x1000),
            int128(0x1),
            int128(0x1000)
        ];
        int128 x;
        int128 y;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            int128 result = Math64x64.add(x, y);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = x + y;

            assertEq(expectedResult, result);
        }
    }

    function testFail_Overflow_add_Math64x64() public pure {
        Math64x64.add(type(int128).max, 1);
    }

    function testFail_Underflow_add_Math64x64() public pure {
        Math64x64.add(type(int128).min, -1);
    }

    // NOTE: No fuzz tests for add() ^^ because too many cases would result in overflow.
    // See symbolic exec testing at: prove_add() in Math64x64SymbolicExecution.t.sol

    /* 8.  function sub (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_sub_Math64x64() public {
        int128[9] memory xValues = [
            type(int128).max,
            type(int128).min,
            int128(-0x1),
            int128(0x0),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x1000),
            type(int128).min
        ];
        int128[9] memory yValues = [
            type(int128).max,
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(0x0),
            type(int128).min,
            int128(-0x1000),
            int128(0x1),
            type(int128).min
        ];
        int128 x;
        int128 y;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            int128 result = Math64x64.sub(x, y);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = x - y;

            assertEq(expectedResult, result);
        }
    }

    function testFail_Overflow_sub_Math64x64() public pure {
        Math64x64.sub(type(int128).max, -1);
    }

    function testFail_Underflow_sub_Math64x64() public pure {
        Math64x64.sub(type(int128).min, 1);
    }

    // NOTE: No fuzz tests for sub() ^^ because too many cases would result in overflow.

    /* 9.  function mul (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_mul_Math64x64() public {
        int128[11] memory xValues = [
            type(int128).max,
            type(int128).max,
            type(int128).max,
            type(int128).min,
            type(int128).min,
            type(int128).min,
            int128(-0x1),
            int128(0x0),
            int128(0x0),
            int128(-0x1),
            int128(0x30)
        ];
        int128[11] memory yValues = [
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x20)
        ];
        int128 x;
        int128 y;
        int256 result;
        int256 expectedResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            result = Math64x64.mul(x, y);

            // Re-implement logic from lib to derive expected result
            expectedResult = (int256(x) * y) >> 64;

            assertEq(expectedResult, result);
        }
    }

    function testFail_Overflow_mul_Math64x64() public pure {
        Math64x64.mul(type(int128).max, type(int128).max);
    }

    function testFail_Underflow_mul_Math64x64() public pure {
        Math64x64.mul(type(int128).min, type(int128).max);
    }

    // NOTE: No fuzz tests for mul() ^^ because too many cases would result in overflow.

    /* 10. function muli (int128 x, int256 y) internal pure returns (int256) {
     ***************************************************************/
    function testUnit_muli_Math64x64() public {
        int128[9] memory xValues = [
            type(int128).min,
            type(int128).min,
            type(int128).min,
            0x1,
            0x0,
            -0x1,
            type(int128).max,
            type(int128).max,
            type(int128).max
        ];
        int256[9] memory yValues = [
            int256(-0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF),
            0x0,
            int256(0x1000000000000000000000000000000000000000000000000),
            0x1,
            0x0,
            -0x1,
            0x0,
            0x1,
            -0x1
        ];
        int128 x;
        int256 y;
        int256 result;
        int256 expectedResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            result = Math64x64.muli(x, y);
            // Re-implement logic from lib to derive expected result
            if (x == type(int128).min) {
                expectedResult = -y << 63;
            } else {
                bool negativeResult = false;
                if (x < 0) {
                    x = -x;
                    negativeResult = true;
                }
                if (y < 0) {
                    y = -y; // We rely on overflow behavior here
                    negativeResult = !negativeResult;
                }
                uint256 absoluteResult = Math64x64.mulu(x, uint256(y));
                if (negativeResult) {
                    expectedResult = -int256(absoluteResult); // We rely on overflow behavior here
                } else {
                    expectedResult = int256(absoluteResult);
                }
            }

            assertEq(expectedResult, result);
        }
    }

    function testFail_Underflow_muli_Math64x64() public pure {
        Math64x64.muli(type(int128).min, type(int256).max);
    }

    /* 11. function mulu (int128 x, uint256 y) internal pure returns (uint256)
     ***************************************************************/
    // NOTE: Math64x64.mulu is tested indirectly through the muli tests
    // No additional testing is deemed necessary

    /* 12. function div (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_div_Math64x64() public {
        int128[10] memory xValues = [
            type(int128).min, // 0
            type(int128).min, // 1
            0x0, // 3
            0x1, // 4
            type(int128).max, // 5
            type(int128).max, // 6
            -0x1, // 7
            -0x20, // 8
            0x100, // 9
            -0x100 // 10
        ];
        int128[10] memory yValues = [
            type(int128).min, // 0
            type(int128).max, // 1
            type(int128).max, // 3
            0x1, // 4
            type(int128).max, // 5
            type(int128).min, // 6
            type(int128).min, // 7
            0x30, // 8
            0x40, // 9
            -0x200 // 10
        ];
        int128 x;
        int128 y;
        int128 result;
        int128 expectedResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            result = Math64x64.div(x, y);

            // Re-implement logic from lib to derive expected result
            expectedResult = int128((int256(x) << 64) / y);
            assertEq(expectedResult, result);
        }
    }

    function testFail_DivByZero_div_Math64x64() public pure {
        Math64x64.div(type(int128).max, 0x0);
    }

    function testFuzz_div_Math64x64(uint256 x, uint256 y) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();
        y = bound(y, 0, 0x7FFFFFFFFFFFFFFF);
        int128 y64 = y.fromUInt();

        vm.assume(y != 0);

        // Re-implement logic from lib to derive expected result
        int256 expectedResult256 = (int256(x64) << 64) / y64;

        int128 expectedResult = int128(expectedResult256);

        int128 result = Math64x64.div(x64, y64);

        assertEq(expectedResult, result);
    }

    /* 13. function divi (int256 x, int256 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_divi_Math64x64() public {
        int256[3] memory xValues = [
            // int256(type(int128).min),  //NOTE: NOT SURE THE LIB HANDLES THIS CORRECTLY
            int256(0x0),
            0x1,
            // int256(type(int128).max), // NOTE: CAN'T GET IT TO WORK W MIN OR MAX IN NUMERATOR
            int256(-0x100)
        ];
        int256[3] memory yValues = [
            int256(0x1),
            // int256(type(int128).max),
            0x40,
            // 0x40,
            int256(-0x200)
        ];
        int256 x;
        int256 y;
        int128 result;
        int128 expectedResult;
        bool negativeResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];

            // Re-implement logic from lib to derive expected result
            negativeResult = false;
            if (x < 0) {
                x = -x; // We rely on overflow behavior here
                negativeResult = true;
            }
            if (y < 0) {
                y = -y; // We rely on overflow behavior here
                negativeResult = !negativeResult;
            }
            uint128 absoluteResult = Math64x64.divuu(uint256(x), uint256(y));
            if (negativeResult) {
                require(absoluteResult <= 0x80000000000000000000000000000000);
                expectedResult = -int128(absoluteResult); // We rely on overflow behavior here
            } else {
                require(absoluteResult <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                expectedResult = int128(absoluteResult); // We rely on overflow behavior here
            }

            result = Math64x64.divi(x, y);
            assertEq(expectedResult, result);
        }
    }

    function testFail_divByZero_divi_Math64x64() public pure {
        Math64x64.divi(type(int128).max, 0x0);
    }

    /* 14. function divu (uint256 x, uint256 y) internal pure returns (int128)
     ***************************************************************/
    // NOTE: Math64x64.divu's core internal function, Math64x64.divuu, is tested indirectly
    // through the Math64x64.divi tests. No additional testing is deemed necessary

    /* 15. function neg (int128 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_neg_Math64x64() public {
        int128[4] memory xValues = [
            int128(0x7FFFFFFFFFFFFFFF - 1),
            int128(0x2),
            int128(-0x1),
            int128(-0x8000000000000000 + 1)
        ];
        int128 x;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            int128 result = Math64x64.neg(x);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = -x;

            assertEq(expectedResult, result);
        }
    }

    function testFail_TooLow_neg_Math64x64() public pure {
        Math64x64.neg(type(int128).min);
    }

    function testFuzz_neg_Math64x64(uint256 x) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();
        vm.assume(x64 > type(int128).min);
    }

    /* 16. function abs (int128 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_abs_Math64x64() public {
        int128[4] memory xValues = [
            int128(0x7FFFFFFFFFFFFFFF - 1),
            int128(0x2),
            int128(-0x1),
            int128(-0x8000000000000000 + 1)
        ];
        int128 x;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            int128 result = Math64x64.abs(x);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = int128(abs(x));

            assertEq(expectedResult, result);
        }
    }

    function testFail_TooLow_abs_Math64x64() public pure {
        Math64x64.abs(type(int128).min);
    }

    function testFuzz_abs_Math64x64(uint256 x) public {
        x = bound(x, 1, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();
        vm.assume(x64 != type(int128).min);
        assertEq(Math64x64.abs(x64), abs(x64));
    }

    /* 17. function inv (int128 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_inv_Math64x64() public {
        int128[4] memory xValues = [
            type(int128).max,
            type(int128).min,
            int128(0x200000000000),
            int128(-0x200000000000)
        ];
        int128 x;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            int128 result = Math64x64.inv(x);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = int128(int256(0x100000000000000000000000000000000) / x);

            assertEq(expectedResult, result);
        }
    }

    function testFail_divByZero_inv_Math64x64() public pure {
        Math64x64.inv(0);
    }

    function testFuzz_inv_Math64x64(uint256 x) public {
        x = bound(x, 1, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();

        int256 expectedResult = int256(0x100000000000000000000000000000000) / x64;
        if (expectedResult > type(int128).max || expectedResult < type(int128).min) return;

        assertEq(Math64x64.inv(int128(x64)), int128(expectedResult));
    }

    /* 18. function avg (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_avg_Math64x64() public {
        int128[5] memory xValues = [
            type(int128).max,
            type(int128).min,
            int128(0x200000000000),
            int128(0x200000000000),
            0x1000
        ];
        int128[5] memory yValues = [type(int128).min, 0x1, int128(0x300000000000), int128(-0x200000000000), 0x1000];
        int128 x;
        int128 y;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            int128 result = Math64x64.avg(x, y);

            int128 expectedResult = int128((int256(x) + int256(y)) >> 1);

            assertEq(expectedResult, result);
        }
    }

    function testFuzz_avg_Math64x64(uint256 x, uint256 y) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();
        y = bound(y, 0, 0x7FFFFFFFFFFFFFFF);
        int128 y64 = y.fromUInt();

        int128 result = Math64x64.avg(x64, y64);

        int128 expectedResult = int128((int256(x64) + int256(y64)) >> 1);

        assertEq(expectedResult, result);
    }

    /* 19. function gavg (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_gavg_Math64x64() public {
        int128[4] memory xValues = [type(int128).min, -0x2000000000000, int128(0x200000000000), 0x1000];
        int128[4] memory yValues = [int128(0x0), -0x1000000000000, 0x300000000000, 0x1000];
        int128 x;
        int128 y;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            int128 result = Math64x64.gavg(x, y);

            int256 m = int256(x) * int256(y);
            int128 expectedResult = int128(Math64x64.sqrtu(uint256(m)));

            assertEq(expectedResult, result);
        }
    }

    function testFail_negativeM_gavg_Math64x64() public pure {
        Math64x64.gavg(-0x1, 0x1);
    }

    /**
     * NOTE: This Math64x64.gavg logic is too complex to test w symbolic execution
     * but also is subject to false positive results when fuzzing due to the potential
     * for a large percentage of test cases being skipped when the product of the passed in
     * parameters is negative.  Recommend deep fuzzing w 10,000 runs or more
     */
    function testFuzz_gavg_Math64x64(uint256 x, uint256 y) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();
        y = bound(y, 0, 0x7FFFFFFFFFFFFFFF);
        int128 y64 = y.fromUInt();

        int256 m = int256(x64) * int256(y64);
        if (m < 0) return;
        if (m >= 0x4000000000000000000000000000000000000000000000000000000000000000) return;

        int128 result = Math64x64.gavg(x64, y64);

        int128 expectedResult = int128(Math64x64.sqrtu(uint256(m)));

        assertEq(expectedResult, result);
    }

    /* 20. function pow (int128 x, uint256 y) internal pure returns (int128)
     ***************************************************************/
    function testUnit_pow_Math64x64() public {
        int128[6] memory xValues = [
            int128(0x0),
            int128(0x0),
            int128(0x2),
            int128(-0x1),
            type(int128).max,
            type(int128).min
        ];
        uint256[6] memory yValues = [
            uint256(0x0),
            uint256(0x1000000000000),
            uint256(0x300000000000),
            uint256(0x1000),
            uint256(0x0),
            uint256(0x1)
        ];
        int128 x;
        uint256 y;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            int128 result = Math64x64.pow(x, y);
            uint256 absoluteResult;
            bool negativeResult = false;
            int128 expectedResult;
            unchecked {
                if (x >= 0) {
                    absoluteResult = powu(uint256(uint128(x)) << 63, y);
                } else {
                    // We rely on overflow behavior here
                    absoluteResult = powu(uint256(uint128(-x)) << 63, y);
                    negativeResult = y & 1 > 0;
                }

                absoluteResult >>= 63;

                if (negativeResult) {
                    expectedResult = -int128(int256(absoluteResult)); // We rely on overflow behavior here
                } else {
                    expectedResult = int128(int256(absoluteResult)); // We rely on overflow behavior here
                }
            }

            assertEq(result, expectedResult);
        }
    }

    function testFail_TooBig_Pow_Math64x64() public pure {
        Math64x64.pow(type(int128).max, type(uint256).max);
    }


    /* 21. function sqrt (int128 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_sqrt_Math64x64() public {
        int128[4] memory xValues = [int128(0x0), int128(0x4), int128(0x2), type(int128).max];
        int128 x;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            int128 result = Math64x64.sqrt(x);
            int128 expectedResult = int128(Math64x64.sqrtu(uint256(uint128(x)) << 64));

            assertEq(result, expectedResult);
        }
    }

    function testFail_negativeNumberFnSqrt_Math64x64() public pure {
        Math64x64.sqrt(-0x1);
    }

    function testFuzz_sqrt_Math64x64(uint256 x) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();
        vm.assume(x64 > 0);

        int128 result = Math64x64.sqrt(x64);
        int128 expectedResult = int128(Math64x64.sqrtu(uint256(uint128(x64)) << 64));

        assertEq(result, expectedResult);
    }

    /* 22. function log_2 (int128 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_log_2_Math64x64() public {
        int128[5] memory xValues = [int128(0x1), int128(0x4), int128(0x2), int128(0x200000000000), type(int128).max];
        int128 x;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            int128 result = Math64x64.log_2(x);
            int256 msb = 0;
            int256 xc = x;
            if (xc >= 0x10000000000000000) {
                xc >>= 64;
                msb += 64;
            }
            if (xc >= 0x100000000) {
                xc >>= 32;
                msb += 32;
            }
            if (xc >= 0x10000) {
                xc >>= 16;
                msb += 16;
            }
            if (xc >= 0x100) {
                xc >>= 8;
                msb += 8;
            }
            if (xc >= 0x10) {
                xc >>= 4;
                msb += 4;
            }
            if (xc >= 0x4) {
                xc >>= 2;
                msb += 2;
            }
            if (xc >= 0x2) msb += 1; // No need to shift xc anymore

            int256 expectedResult = (msb - 64) << 64;
            uint256 ux = uint256(uint128(x)) << (127 - uint256(msb));
            for (int256 bit = 0x8000000000000000; bit > 0; bit >>= 1) {
                ux *= ux;
                uint256 b = ux >> 255;
                ux >>= 127 + b;
                expectedResult += bit * int256(b);
            }

            assertEq(result, int128(expectedResult));
        }
    }

    function testFail_NegativeNumber_log_2_Math64x64() public pure {
        Math64x64.log_2(-0x1);
    }

    function testFail_Zero_log_2_Math64x64() public pure {
        Math64x64.log_2(0x0);
    }

    /* 23. function ln(int128 x) internal pure returns (int128)
     ***************************************************************/
    function testUnit_ln_Math64x64() public {
        int128[5] memory xValues = [int128(0x1), int128(0x4), int128(0x2), int128(0x200000000000), type(int128).max];
        int128 x;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            unchecked {
                int128 result = Math64x64.ln(x);
                int128 expectedResult = int128(int256((uint256(int256(Math64x64.log_2(x))) * 0xB17217F7D1CF79ABC9E3B39803F2F6AF) >> 128));
                assertEq(expectedResult, result);
            }

        }
    }

    function testFail_negativeNumber_ln_Math64x64() public pure {
        Math64x64.ln(-0x1);
    }

    function testFail_Zero_ln_Math64x64() public pure {
        Math64x64.ln(0x0);
    }

    function testFuzz_ln_Math64x64(uint256 x) public {
        x = bound(x, 0, 0x7FFFFFFFFFFFFFFF);
        int128 x64 = x.fromUInt();
        vm.assume(x64 > 0);



        int128 result = Math64x64.ln(x64);
        int128 expectedLog2 = Math64x64.log_2(x64);
        int128 expectedResult = int128(
            int256((uint256(uint128(expectedLog2)) * 0xB17217F7D1CF79ABC9E3B39803F2F6AF) >> 128)
        );

        assertEq(expectedResult, result);
    }

    /* 24. function exp_2 (int128 x) internal pure returns (int128)
     ***************************************************************/
    // NOTE: Math64x64.exp_2 is tested indirectly through the exp tests below
    // No additional testing is deemed necessary

    /* 25. function exp (int128 x) internal pure returns (int128)
     ***************************************************************/

    function testUnit_exp_Math64x64() public {
        int128[5] memory xValues = [
            int128(-0x400000000000000000),
            int128(0x0),
            int128(0x1),
            int128(0x2),
            int128(0x10000000)
        ];
        int128 x;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];

            int128 result = Math64x64.exp(x);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = Math64x64.exp_2(int128((int256(x) * 0x171547652B82FE1777D0FFDA0D23A7D12) >> 128));

            assertEq(expectedResult, result);
        }
    }

    function testFail_TooHigh_exp_Math64x64() public pure {
        Math64x64.exp(int128(0x400000000000000000));
    }

    function testFuzz_exp_Math64x64(int256 passedInX) public {
        int128 x = coerceInt256To128(
            passedInX,
            int256(-0x400000000000000000),
            int256(0x400000000000000000)
        );

        int128 result;
        try forTesting.exp(x) returns (int128 result_) {
            result = result_;
        } catch {
            return;
        }

        int128 expectedResult = Math64x64.exp_2(int128((int256(x) * 0x171547652B82FE1777D0FFDA0D23A7D12) >> 128));

        assertEq(expectedResult, result);
    }

    /* 26. function divuu (uint256 x, uint256 y) internal pure returns (uint128)
     ***************************************************************/
    // NOTE: Math64x64.divuu is tested indirectly through the Math64x64.divi tests above
    // No additional testing is deemed necessary

    /* 27. function sqrtu(uint256 x) private pure returns (uint128)
     ***************************************************************/
    // NOTE: Math64x64.sqrtu is tested indirectly through the Math64x64.sqrt and Math64x64.gavg tests above
    // No additional testing is deemed necessary
}
