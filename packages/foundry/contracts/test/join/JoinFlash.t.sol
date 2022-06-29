// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "../../mocks/DAIMock.sol";
import {FlashJoin} from "../../FlashJoin.sol";
import "../utils/Utilities.sol";
import "../utils/Test.sol";
import "../utils/TestConstants.sol";

import {FlashBorrower} from "erc3156/contracts/FlashBorrower.sol";

abstract contract ZeroState is Test, TestConstants {
    event FlashFeeFactorSet(uint256 indexed fee);

    DAIMock public token;
    FlashJoin public join;
    Utilities internal utils;
    FlashBorrower public borrower;

    address internal admin;
    address internal other;

    struct Actions {
        string none;
        string transfer;
        string steal;
        string reenter;
    }

    Actions actions =
        Actions(
            "0x0000000000000000000000000000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000000000000000000000000001",
            "0x0000000000000000000000000000000000000000000000000000000000000002",
            "0x0000000000000000000000000000000000000000000000000000000000000003"
        );

    function setUp() public virtual {
        utils = new Utilities();

        token = new DAIMock();
        join = new FlashJoin(address(token));
        borrower = new FlashBorrower(join);

        admin = address(0xa11ce);
        other = address(0xb0b);

        join.grantRole(join.join.selector, admin);
        join.grantRole(join.exit.selector, admin);
        join.grantRole(join.retrieve.selector, admin);
        join.grantRole(join.setFlashFeeFactor.selector, admin);

        token.mint(address(join), WAD * 100);
        vm.prank(admin);
        join.join(admin, uint128(WAD * 100));
    }
}

contract JoinFlashTest is ZeroState {
    function testFlashDisabledByDefault() public {
        vm.expectRevert(stdError.arithmeticError);
        join.flashLoan(borrower, address(token), WAD, bytes(actions.none));
    }

    function testSetsFlashFeeFactor() public {
        uint256 feeFactor = (WAD * 5) / 100; // 5%
        vm.prank(admin);

        vm.expectEmit(true, false, false, false);
        emit FlashFeeFactorSet(feeFactor);
        join.setFlashFeeFactor(feeFactor);
        assertEq(join.flashFeeFactor(), feeFactor);
    }
}

abstract contract WithFee is ZeroState {
    function setUp() public override {
        super.setUp();

        uint256 feeFactor = 0;
        vm.prank(admin);
        join.setFlashFeeFactor(feeFactor);
    }
}

contract JoinFlashWithFee is WithFee {
    function testRevertsWithoutRepayApproval() public {
        vm.prank(address(borrower));
        vm.expectRevert();
        join.flashLoan(borrower, address(token), WAD, bytes(actions.none));
    }

    function testFlashNoFee() public {
        borrower.flashBorrow(address(token), WAD);

        assertEq(token.balanceOf(admin), 0);
        assertEq(borrower.flashBalance(), WAD);
        assertEq(borrower.flashToken(), address(token));
        assertEq(borrower.flashAmount(), WAD);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testRevertsWithInsuffienctBalance() public {
        vm.expectRevert("ERC20: Insufficient approval");
        borrower.flashBorrowAndSteal(address(token), WAD);
    }

    function testTwoNestedFlash() public {
        borrower.flashBorrowAndReenter(address(token), WAD); // It will borrow WAD, and then reenter and borrow WAD * 2
        assertEq(borrower.flashBalance(), WAD * 3);
    }

    function testFlashWithNonZeroFee() public {
        uint256 feeFactor = (WAD * 5) / 100; // 5%
        vm.prank(admin);
        join.setFlashFeeFactor(feeFactor);

        uint256 principal = WAD;
        uint256 fee = feeFactor;
        token.mint(address(borrower), fee);

        borrower.flashBorrow(address(token), principal);

        assertEq(token.balanceOf(admin), 0);
        assertEq(borrower.flashBalance(), principal + fee);
        assertEq(borrower.flashToken(), address(token));
        assertEq(borrower.flashAmount(), principal);
        assertEq(borrower.flashInitiator(), address(borrower));
    }
}
