// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "../../mocks/DAIMock.sol";
import "../../FlashJoin.sol";
import "../utils/Utilities.sol";
import "../utils/Test.sol";
import "../utils/TestConstants.sol";

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/FlashBorrower.sol";

contract JoinFlashTest is Test, TestConstants {
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

    function setUp() public {
        Actions actions = new Actions();
        actions
            .none = "0x0000000000000000000000000000000000000000000000000000000000000000";
        actions
            .transfer = "0x0000000000000000000000000000000000000000000000000000000000000001";
        actions
            .steal = "0x0000000000000000000000000000000000000000000000000000000000000002";
        actions
            .reenter = "0x0000000000000000000000000000000000000000000000000000000000000003";

        utils = new Utilities();

        token = new DAIMock();
        join = new FlashJoin(address(token));
        borrower = new FlashBorrower();

        admin = address(0xa11ce);
        other = address(0xb0b);

        join.grantRole(join.join.selector, admin);
        join.grantRole(join.exit.selector, admin);
        join.grantRole(join.retrieve.selector, admin);
        join.grantRole(join.setFlashFeeFactor.selector, admin);

        token.mint(address(join), WAD * 100);
        vm.prank(admin);
        join.join(admin, WAD * 100);
    }

    function testFlashDisabledByDefault() public {
        vm.expectRevert(
            join.flashLoan(address(borrower), token, WAD, Actions.none)
        );
    }

    // with zero fee
    function testRevertsWithoutApproval() public {}

    // with zero fee
    function testFlashNoFee() public {}

    // with zero fee
    function testCanRepayByTransfer() public {}

    // with zero fee
    function testRevertsWithInsuffienctBalance() public {}

    // with zero fee
    function testTwoNestedFlash() public {}

    // with zero fee
    function testSetsFlashFeeFactor() public {}

    // with non-zero fee
    function testFlashWithFee() public {}
}
