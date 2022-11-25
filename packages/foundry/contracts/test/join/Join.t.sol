// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { TestExtensions } from "../TestExtensions.sol";
import { Join } from "../../Join.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions {

    Join public join; 
    IERC20 public token;
    uint128 public unit;
    IERC20 public otherToken;
    uint128 public otherUnit;
        
    address admin;
    address user;
    address other;
    address deployer;

    function setUp() public virtual {
        vm.createSelectFork('mainnet');

        //... Users ...
        admin = address(1);
        user = address(2);
        other = address(3);
        vm.label(admin, "admin");
        vm.label(user, "user");
        vm.label(other, "other");
        
        deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        vm.label(deployer, "deployer");

        //... Contracts ...
        token = IERC20(address(new ERC20Mock("", "")));
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());
        vm.label(address(token), "token");

        otherToken = IERC20(address(new ERC20Mock("", "")));
        otherUnit = uint128(10 ** ERC20Mock(address(otherToken)).decimals());
        vm.label(address(otherToken), "otherToken");

        //... Deploy Joins and grant access ...
        join = new Join(address(token));
        vm.label(address(join), "join");

        //... Permissions ...
        join.grantRole(Join.join.selector, admin);
        join.grantRole(Join.exit.selector, admin);
        join.grantRole(Join.retrieve.selector, admin);

        cash(token, user, 100 * unit);
    }  
}

contract DeployedTest is Deployed {

    function testJoinAuth() public {
        vm.expectRevert("Access denied");
        vm.prank(user);
        join.join(user, unit);
    }

    function testExitAuth() public {
        vm.expectRevert("Access denied");
        vm.prank(user);
        join.exit(user, unit);
    }

    function testRetrieveAuth() public {
        vm.expectRevert("Access denied");
        vm.prank(user);
        join.retrieve(otherToken, other);
    }
    
    function testJoinPull() public {
        track("userBalance", token.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", token.balanceOf(address(join)));

        vm.prank(user);
        token.approve(address(join), unit);
        vm.prank(admin);
        join.join(user, unit);

        assertTrackMinusEq("userBalance", unit, token.balanceOf(user));
        assertTrackPlusEq("storedBalance", unit, join.storedBalance());
        assertTrackPlusEq("joinBalance", unit, token.balanceOf(address(join)));
    }

    function testJoinPush() public {
        track("userBalance", token.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", token.balanceOf(address(join)));

        vm.prank(user);
        token.transfer(address(join), unit);
        vm.prank(admin);
        join.join(user, unit);

        assertTrackMinusEq("userBalance", unit, token.balanceOf(user));
        assertTrackPlusEq("storedBalance", unit, join.storedBalance());
        assertTrackPlusEq("joinBalance", unit, token.balanceOf(address(join)));
    }

    function testJoinCombine() public {
        track("userBalance", token.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", token.balanceOf(address(join)));

        vm.prank(user);
        token.approve(address(join), unit/2);
        vm.prank(user);
        token.transfer(address(join), unit/2);
        vm.prank(admin);
        join.join(user, unit);

        assertTrackMinusEq("userBalance", unit, token.balanceOf(user));
        assertTrackPlusEq("storedBalance", unit, join.storedBalance());
        assertTrackPlusEq("joinBalance", unit, token.balanceOf(address(join)));
    }
}

abstract contract WithTokens is Deployed {
    function setUp() public override virtual {
        super.setUp();

        vm.prank(user);
        token.transfer(address(join), unit);
        vm.prank(admin);
        join.join(user, unit);

    }
}

contract WithTokensTest is WithTokens {

    function testExit() public {
        track("otherBalance", token.balanceOf(other));
        track("storedBalance", join.storedBalance());
        track("joinBalance", token.balanceOf(address(join)));

        vm.prank(admin);
        join.exit(other, unit);

        assertTrackPlusEq("otherBalance", unit, token.balanceOf(other));
        assertTrackMinusEq("storedBalance", unit, join.storedBalance());
        assertTrackMinusEq("joinBalance", unit, token.balanceOf(address(join)));
    }
}

abstract contract WithOtherTokens is Deployed {
    function setUp() public override virtual {
        super.setUp();

        cash(otherToken, address(join), 100 * otherUnit);
    }
}

contract WithOtherTokensTest is WithOtherTokens {

    function testRetrieve() public {
        uint256 retrievedTokens = otherToken.balanceOf(address(join));
        track("otherBalance", otherToken.balanceOf(other));
        track("joinBalance", otherToken.balanceOf(address(join)));

        vm.prank(admin);
        join.retrieve(otherToken, other);

        assertTrackPlusEq("otherBalance", retrievedTokens, otherToken.balanceOf(other));
        assertTrackMinusEq("joinBalance", retrievedTokens, otherToken.balanceOf(address(join)));
    }
}


    
// Deployed
// join
// exit
// WithTokens
// join
// exit
// WithOtherTokens
// retrieve
