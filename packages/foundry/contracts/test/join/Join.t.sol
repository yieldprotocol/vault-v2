// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { TestExtensions } from "../TestExtensions.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { Join } from "../../Join.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions, TestConstants {

    Join public join; 
    IERC20 public token;
    uint128 public unit;
    IERC20 public otherToken;
    uint128 public otherUnit;
        
    address user;
    address other;
    address ladle;
    address me;

    function setUpMock() public {
        ladle = address(3);

        //... Contracts ...
        token = IERC20(address(new ERC20Mock("", "")));
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());

        otherToken = IERC20(address(new ERC20Mock("", "")));
        otherUnit = uint128(10 ** ERC20Mock(address(otherToken)).decimals());

        //... Deploy Joins and grant access ...
        join = new Join(address(token));

        //... Permissions ...
        join.grantRole(Join.join.selector, ladle);
        join.grantRole(Join.exit.selector, ladle);
        join.grantRole(Join.retrieve.selector, ladle);
    }

    function setUpHarness(string memory network) public {
        ladle = addresses[network][LADLE];

        join = Join(vm.envAddress("JOIN"));
        token = IERC20(join.asset());
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());

        otherToken = IERC20(address(new ERC20Mock("", "")));
        otherUnit = uint128(10 ** ERC20Mock(address(otherToken)).decimals());

        // Grant ladle permissions to retrieve tokens, since no one has them.
        vm.prank(addresses[network][TIMELOCK]);
        join.grantRole(Join.retrieve.selector, ladle);
    }

    function setUp() public virtual {
        string memory network = vm.envOr(NETWORK, LOCALHOST);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);

        //... Users ...
        user = address(1);
        other = address(2);
        me = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

        vm.label(ladle, "ladle");
        vm.label(user, "user");
        vm.label(other, "other");
        vm.label(me, "me");
        vm.label(address(token), "token");
        vm.label(address(otherToken), "otherToken");
        vm.label(address(join), "join");

        cash(token, user, 100 * unit);

        // If there are any unclaimed assets in the Join, join them.
        uint128 unclaimedTokens = uint128(token.balanceOf(address(join)) - join.storedBalance());
        vm.prank(ladle);
        join.join(address(join), unclaimedTokens);
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
        vm.prank(ladle);
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
        vm.prank(ladle);
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
        vm.prank(ladle);
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
        vm.prank(ladle);
        join.join(user, unit);

    }
}

contract WithTokensTest is WithTokens {

    function testExit() public {
        track("otherBalance", token.balanceOf(other));
        track("storedBalance", join.storedBalance());
        track("joinBalance", token.balanceOf(address(join)));

        vm.prank(ladle);
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

        vm.prank(ladle);
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
