// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";
import {FlashBorrower} from "../../mocks/FlashBorrower.sol";

abstract contract VYTokenZeroState is ZeroState {
    address public timelock;
    FlashBorrower public borrower;

    function setUp() public virtual override {
        super.setUp();
        timelock = address(1);
        vyToken.grantRole(VYToken.point.selector, address(timelock));
        vyToken.grantRole(VYToken.mint.selector, address(this));
        vyToken.grantRole(VYToken.deposit.selector, address(this));
        vyToken.grantRole(VYToken.setFlashFeeFactor.selector, address(this));

        borrower = new FlashBorrower(vyToken);
        unit = uint128(10**ERC20Mock(address(vyToken)).decimals());
        user = address(this);
        deal(address(vyToken), address(this), unit);
        deal(address(vyToken.underlying()), address(this), unit);
    }
}

contract VYTokenTest is VYTokenZeroState {
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

    function testRevertsOnInvalidPoint() public {
        console.log("reverts on invalid point");
        vm.prank(timelock);
        vm.expectRevert("Unrecognized parameter");
        vyToken.point("invalid", address(this));
    }

    function testMintWithUnderlying() public {
        console.log("can mint with underlying");
        track("userTokenBalance", vyToken.balanceOf(user));

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );

        vyToken.mint(user, unit);

        assertTrackPlusEq("userTokenBalance", unit, vyToken.balanceOf(user));
    }

    function testDepositToMint() public {
        console.log("can deposit to mint");
        track("userTokenBalance", vyToken.balanceOf(user));
        track(
            "userUnderlyingBalance",
            IERC20(vyToken.underlying()).balanceOf(user)
        );

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );

        vyToken.deposit(user, unit);

        assertTrackPlusEq("userTokenBalance", unit, vyToken.balanceOf(user));
        assertTrackMinusEq(
            "userUnderlyingBalance",
            unit,
            IERC20(vyToken.underlying()).balanceOf(user)
        );
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

    function testWithdraw() public {
        console.log("can withdraw principal");
        track("userTokenBalance", vyToken.balanceOf(address(this)));
        track(
            "userUnderlyingBalance",
            IERC20(vyToken.underlying()).balanceOf(address(this))
        );

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );

        vyToken.mint(address(this), unit);

        vyToken.withdraw(unit, address(this), address(this));
        assertTrackPlusEq(
            "userTokenBalance",
            0,
            vyToken.balanceOf(address(this))
        );

        assertEq(unit, IERC20(vyToken.underlying()).balanceOf(address(this)));
    }

    function testRedeem() public {
        console.log("can redeem underlying");
        track("userTokenBalance", vyToken.balanceOf(user));
        track(
            "userUnderlyingBalance",
            IERC20(vyToken.underlying()).balanceOf(user)
        );

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );
        vyToken.mint(user, unit);

        vyToken.redeem(unit, user, user);

        assertTrackPlusEq("userTokenBalance", 0, vyToken.balanceOf(user));
        assertEq(unit, IERC20(vyToken.underlying()).balanceOf(address(this)));
    }

    function testFlashFeeFactor() public {
        console.log("can set the flash fee factor");
        assertEq(vyToken.flashFeeFactor(), type(uint256).max);
        vyToken.setFlashFeeFactor(1);
        assertEq(vyToken.flashFeeFactor(), 1);
    }
}

abstract contract FlashLoanEnabledState is VYTokenZeroState {
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    function setUp() public override {
        super.setUp();
        vyToken.setFlashFeeFactor(0);
    }
}

contract FlashLoanEnabledStateTests is FlashLoanEnabledState {
    function testReturnsCorrectMaxFlashLoan() public {
        console.log("can return the correct max flash loan");
        assertEq(vyToken.maxFlashLoan(address(vyToken)), type(uint256).max);
    }

    function testFlashBorrow() public {
        console.log("can do a simple flash borrow");

        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.NORMAL
        );

        assertEq(vyToken.balanceOf(user), 0);
        assertEq(borrower.flashBalance(), unit);
        assertEq(borrower.flashToken(), address(vyToken));
        assertEq(borrower.flashAmount(), unit);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testRepayWithTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(vyToken), address(0), unit);

        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.TRANSFER
        );

        assertEq(vyToken.balanceOf(user), 0);
        assertEq(borrower.flashBalance(), unit);
        assertEq(borrower.flashToken(), address(vyToken));
        assertEq(borrower.flashAmount(), unit);
        assertEq(borrower.flashFee(), 0);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testApproveNonInitiator() public {
        vm.expectRevert("ERC20: Insufficient approval");
        vm.prank(user);
        vyToken.flashLoan(
            borrower,
            address(vyToken),
            unit,
            bytes(abi.encode(0))
        );
    }

    function testEnoughFundsForLoanRepay() public {
        vm.expectRevert("ERC20: Insufficient balance");
        vm.prank(user);
        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.STEAL
        );
    }

    function testNestedFlashLoans() public {
        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.REENTER
        );
        vm.prank(user);
        assertEq(borrower.flashBalance(), unit * 3);
    }
}
