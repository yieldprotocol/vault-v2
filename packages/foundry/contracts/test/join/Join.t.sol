// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "../../mocks/DAIMock.sol";
import "../../mocks/USDCMock.sol";
import "../../Join.sol";
import "../utils/Utilities.sol";
import "../utils/Test.sol";
import "../utils/TestConstants.sol";

contract JoinTest is Test, TestConstants {
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    DAIMock public token;
    USDCMock public otherToken;
    Join public join;
    Utilities internal utils;

    address internal admin;
    address internal other;

    function setUp() public {
        utils = new Utilities();

        token = new DAIMock();
        otherToken = new USDCMock();
        join = new Join(address(token));

        admin = address(0xa11ce);
        other = address(0xb0b);

        join.grantRole(join.join.selector, admin);
        join.grantRole(join.exit.selector, admin);
        join.grantRole(join.retrieve.selector, admin);

        token.mint(admin, WAD * 100);
        vm.prank(admin);
        token.approve(address(join), WAD * 100);
    }

    function testRetrievesAirdroppedTokens() public {
        otherToken.mint(address(join), WAD);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(join), admin, WAD);

        vm.prank(admin);
        join.retrieve(otherToken, admin);
    }

    function testPullsTokensFromUser() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(admin, address(join), WAD);

        vm.prank(admin);
        join.join(admin, uint128(WAD));

        assertEq(join.storedBalance(), WAD);
    }

    // with tokens in the join
    function testAcceptsSurplusAsTransfer() public {
        token.mint(address(join), WAD);

        vm.prank(admin);
        join.join(admin, uint128(WAD));
        assertEq(join.storedBalance(), WAD);
    }

    function testCombinesSurplusAndTokensFromUser() public {
        token.mint(address(join), WAD);

        vm.expectEmit(true, true, false, true);
        emit Transfer(admin, address(join), WAD);

        vm.prank(admin);
        join.join(admin, uint128(WAD * 2));

        assertEq(join.storedBalance(), WAD * 2);
    }

    // with positive stored balance
    function testPushesTokensToUser() public {
        vm.prank(admin);
        join.join(admin, uint128(WAD));

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(join), admin, WAD);

        vm.prank(admin);
        join.exit(admin, uint128(WAD));
        assertEq(join.storedBalance(), 0);
    }
}
