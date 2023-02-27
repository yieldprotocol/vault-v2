// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "src/utils/Math.sol";

contract FixedPointMathLibTest is DSTest {
    // test a couple of concrete cases
    function testWPow() public {
        assertEq(Math.wpow(2e18, 2), 4e18);
        assertEq(Math.wpow(2e18, 4), 16e18);

        assertEq(Math.wpow(0, 0), 1e18);
        assertEq(Math.wpow(0, 1), 0);
        assertEq(Math.wpow(0, 10), 0);

        assertEq(Math.wpow(1, 0), 1e18);
        assertEq(Math.wpow(1e18, 0), 1e18);
    }

    // helper method
    function testWPowImpl(uint256 x, uint256 n) internal {
        uint256 expected = 1e18;
        if (n > 0) {
            expected = x;
        }
        bool expectExpectedToIncrease = (x > 1e18);
        if (n > 1) {
            for (uint256 i = 1; i < n; ++i) {
                unchecked {
                    uint256 old_expected = expected;
                    expected = (expected * x) / 1e18;
                    // check for overflow if x > 1
                    if (expectExpectedToIncrease && expected < old_expected) {
                        return;
                    }
                    // check if we reached precision limits and
                    // can save a bit of CPU
                    if (expected == old_expected) {
                        break;
                    }
                }
            }
        }
        uint256 result = Math.wpow(x, n);
        uint256 distance = (result > expected)
            ? result - expected
            : expected - result;
        emit log_uint(x);
        emit log_uint(expected);
        emit log_uint(result);
        emit log_uint(distance);
        // only allow 3 decimals of precision loss
        //
        // IMPORTANT: the 'expected' value is not the *true* value b/c it also suffers from
        // precision loss.
        // An alternative approach to compute the *true* expected value is to use HEVM `ffi` cheat code
        // to call an external process (nodejs/python with bigint library) to do the computation
        uint256 acceptable_epsilon = result / 1e15;
        // if x < 1e18, we're allowed to lose 1 wei of precision on each iteration
        if (acceptable_epsilon < n) {
            acceptable_epsilon = n;
        }
        assertLe(distance, acceptable_epsilon);
    }

    // pick a random delta_x from [0, 1]
    // pick a random n between 0 and 1000
    // set `x = 1 +/- delta_x` to test an x value from [0, 2]
    // check that wpow(x, y) is roughly the same as manual x * x * ... * x (n times)
    // 'roughly the same': the diff is smaller than result * 1e-15
    //
    function testWPowBetween0and2(uint64 delta_x, uint16 n) public {
        delta_x = delta_x % 1e18;
        n = n % 1000; // only test up to n=1k - it's too slow to go beyond that
        // see the `ffi` note above on how to test above 1k
        testWPowImpl(1e18 + delta_x, n);
        testWPowImpl(1e18 - delta_x, n);
    }
}
