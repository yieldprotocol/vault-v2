// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/Test.sol";

contract MyTest is Test {
    function testMe() public {
        console.log("hello");
        uint256 x = 5;
        assertEq(x, 5);
    }
}
