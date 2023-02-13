// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";

abstract contract VYTokenZeroState is ZeroState {
    address public timelock;

    function setUp() public override {
        super.setUp();
        timelock = address(1);
        vyToken.grantRole(VYToken.point.selector, address(timelock));
        vyToken.grantRole(VYToken.mint.selector, address(ladle));
    }
}

contract FYTokenTest is VYTokenZeroState {
    function testChangeOracle() public {
        console.log("can change the CHI oracle");
        vm.expectEmit(true, false, false, true);
        emit Point("oracle", address(this));
        vm.prank(timelock);
        vyToken.point("oracle", address(this));
        assertEq(address(vyToken.oracle()), address(this));
    }

    function testChangeJoin() public {
        console.log("can change Join");
        vm.expectEmit(true, false, false, true);
        emit Point("join", address(this));
        vm.prank(timelock);
        vyToken.point("join", address(this));
        assertEq(address(vyToken.join()), address(this));
    }

    function testMintWithUnderlying() public {
        console.log("can mint with underlying");
        track("userTokenBalance", vyToken.balanceOf(user));

        vm.prank(address(ladle));
        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );
        vm.prank(address(ladle));
        vyToken.mint(user, unit);

        assertTrackPlusEq("userTokenBalance", unit, vyToken.balanceOf(user));
    }

    function testConvertToPrincipal() public {
        console.log("can convert amount of underlying to principal");
        assertEq(vyToken.convertToPrincipal(unit), unit);
    }

    function testConvertToUnderlying() public {
        console.log("can convert amount of principal to underlying");
        assertEq(vyToken.convertToUnderlying(unit), unit);
    }

    function testPreviewRedeem() public {
        console.log("can preview the amount of underlying redeemed");
        assertEq(vyToken.previewRedeem(unit), unit);
    }

    function testPreviewWithdraw() public {
        console.log("can preview the amount of principal withdrawn");
        assertEq(vyToken.previewWithdraw(unit), unit);
    }
}
