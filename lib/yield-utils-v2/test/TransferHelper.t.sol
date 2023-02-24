// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/token/TransferHelper.sol";
import "../src/token/IERC20.sol";

contract TransferHelperTest is Test {
    using TransferHelper for IERC20;

    IERC20 usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address other = address(123);

    function setUp() public {
        vm.createSelectFork("mainnet");

        deal(address(usdt), address(this), 100);
    }

    function testSafeApprove() public {
        console.log("can successfully safe approve");
        usdt.safeApprove(other, 100);
        assertEq(
            usdt.allowance(address(this), other), 
            100
        );
    }

    function testZeroValue() public {
        console.log("can safe approve with zero value");
        usdt.safeApprove(other, 50);
        assertEq(
            usdt.allowance(address(this), other),
            50
        );
        // will reset existing allowance
        usdt.safeApprove(other, 0);
        assertEq(
            usdt.allowance(address(this), other),
            0
        );
    }
}
