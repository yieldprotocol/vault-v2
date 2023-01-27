// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { TestExtensions } from "../../utils/TestExtensions.sol";
import { TestConstants } from "../../utils/TestConstants.sol";
import { IUSDT } from "../../../other/tether/IUSDT.sol";
import { TetherJoin } from "../../../other/tether/TetherJoin.sol";
import { ERC20Mock } from "../../../mocks/ERC20Mock.sol";

using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions, TestConstants {

    TetherJoin public join; 
    IUSDT public tether;
    uint128 public unit;
    IERC20 public otherToken;
    uint128 public otherUnit;
        
    address user;
    address other;
    address ladle;
    address me;
    address tetherMultiSig;

    function setUpMock() public {
        vm.createSelectFork(MAINNET);

        ladle = addresses[MAINNET][LADLE];

        //... Contracts ...
        tether = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        unit = uint128(10 ** ERC20Mock(address(tether)).decimals());

        otherToken = IERC20(address(new ERC20Mock("", "")));
        otherUnit = uint128(10 ** ERC20Mock(address(otherToken)).decimals());

        //... Deploy Joins and grant access ...
        join = new TetherJoin(address(tether));

        //... Permissions ...
        join.grantRole(TetherJoin.join.selector, ladle);
        join.grantRole(TetherJoin.exit.selector, ladle);
        join.grantRole(TetherJoin.retrieve.selector, ladle);
    }

    function setUpHarness(string memory network) public {
        ladle = addresses[network][LADLE];

        join = TetherJoin(vm.envAddress("JOIN"));
        tether = IUSDT(join.asset());
        unit = uint128(10 ** ERC20Mock(address(tether)).decimals());

        otherToken = IERC20(address(new ERC20Mock("", "")));
        otherUnit = uint128(10 ** ERC20Mock(address(otherToken)).decimals());

        // Grant ladle permissions to retrieve tokens, since no one has them.
        vm.prank(addresses[network][TIMELOCK]);
        join.grantRole(TetherJoin.retrieve.selector, ladle);
    }

    function setUp() public virtual {
        string memory network = vm.envOr(NETWORK, LOCALHOST);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);

        //... Users ...
        user = address(0xdeadbeef);
        other = address(2);
        me = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        tetherMultiSig = 0xC6CDE7C39eB2f0F0095F41570af89eFC2C1Ea828;

        vm.label(ladle, "ladle");
        vm.label(user, "user");
        vm.label(other, "other");
        vm.label(me, "me");
        vm.label(address(tether), "tether");
        vm.label(tetherMultiSig, "tetherMultiSig");
        vm.label(address(otherToken), "otherToken");
        vm.label(address(join), "join");

        deal(address(tether), user, 100 * unit);

        // If there are any unclaimed assets in the Join, join them.
        uint128 unclaimedTokens = uint128(tether.balanceOf(address(join)) - join.storedBalance());
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
        track("userBalance", tether.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", tether.balanceOf(address(join)));

        vm.prank(user);
        tether.approve(address(join), unit);
        vm.prank(ladle);
        join.join(user, unit);

        assertTrackMinusEq("userBalance", unit, tether.balanceOf(user));
        assertTrackPlusEq("storedBalance", unit, join.storedBalance());
        assertTrackPlusEq("joinBalance", unit, tether.balanceOf(address(join)));
    }

    function testJoinPush() public {
        track("userBalance", tether.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", tether.balanceOf(address(join)));

        vm.prank(user);
        tether.transfer(address(join), unit);
        vm.prank(ladle);
        join.join(user, unit);

        assertTrackMinusEq("userBalance", unit, tether.balanceOf(user));
        assertTrackPlusEq("storedBalance", unit, join.storedBalance());
        assertTrackPlusEq("joinBalance", unit, tether.balanceOf(address(join)));
    }

    function testJoinCombine() public {
        track("userBalance", tether.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", tether.balanceOf(address(join)));

        vm.prank(user);
        tether.approve(address(join), unit / 2);
        vm.prank(user);
        tether.transfer(address(join), unit / 2);
        vm.prank(ladle);
        join.join(user, unit);

        assertTrackMinusEq("userBalance", unit, tether.balanceOf(user));
        assertTrackPlusEq("storedBalance", unit, join.storedBalance());
        assertTrackPlusEq("joinBalance", unit, tether.balanceOf(address(join)));
    }
}

abstract contract WithFees is Deployed {
    function setUp() public override virtual {
        super.setUp();

        // enable fees
        vm.prank(tetherMultiSig);
        tether.setParams(19, 49);    // maximum
    }
}

contract WithFeesTest is WithFees {
    function testJoinPullWithFees() public {
        track("userBalance", tether.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", tether.balanceOf(address(join)));

        uint256 units = unit * 5;
        uint256 fee = tether.basisPointsRate() * 100;
        uint256 feeAdjustedUnits = units * unit / (unit - fee); // scale up first so precision isn't lost

        vm.prank(user);
        tether.approve(address(join), feeAdjustedUnits);
        vm.prank(ladle);
        join.join(user, uint128(feeAdjustedUnits));

        assertTrackMinusEq("userBalance", feeAdjustedUnits, tether.balanceOf(user));
        assertTrackPlusEq("storedBalance", units, join.storedBalance());
        assertTrackPlusEq("joinBalance", units, tether.balanceOf(address(join)));
    }

    function testJoinPushWithFees() public {
        track("userBalance", tether.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", tether.balanceOf(address(join)));

        uint256 units = unit * 5;
        uint256 fee = tether.basisPointsRate() * 100;
        uint256 feeAdjustedUnits = units * unit / (unit - fee); // scale up first so precision isn't lost

        vm.prank(user);
        tether.transfer(address(join), feeAdjustedUnits);
        vm.prank(ladle);
        join.join(user, uint128(units));

        assertTrackMinusEq("userBalance", feeAdjustedUnits, tether.balanceOf(user));
        assertTrackPlusEq("storedBalance", units, join.storedBalance());
        assertTrackPlusEq("joinBalance", units, tether.balanceOf(address(join)));
    }

    function testJoinCombineWithFees() public {
        track("userBalance", tether.balanceOf(user));
        track("storedBalance", join.storedBalance());
        track("joinBalance", tether.balanceOf(address(join)));

        uint256 units = unit * 13;
        uint256 fee = tether.basisPointsRate() * 100;
        uint256 feeAdjustedUnits = units / 2 * unit / (unit - fee); // scale up first so precision isn't lost

        vm.prank(user);
        tether.approve(address(join), feeAdjustedUnits);
        vm.prank(user);
        tether.transfer(address(join), feeAdjustedUnits);
        vm.prank(ladle);
        join.join(user, uint128(units));

        assertTrackMinusEq("userBalance", feeAdjustedUnits * 2, tether.balanceOf(user));
        assertTrackPlusEq("storedBalance", units, join.storedBalance());
        assertTrackPlusEq("joinBalance", units, tether.balanceOf(address(join)));
    }
}

abstract contract WithTokens is Deployed {
    function setUp() public override virtual {
        super.setUp();

        vm.prank(user);
        tether.transfer(address(join), unit);
        vm.prank(ladle);
        join.join(user, unit);
    }
}

contract WithTokensTest is WithTokens {

    function testExit() public {
        track("otherBalance", tether.balanceOf(other));
        track("storedBalance", join.storedBalance());
        track("joinBalance", tether.balanceOf(address(join)));

        vm.prank(ladle);
        join.exit(other, unit);

        assertTrackPlusEq("otherBalance", unit, tether.balanceOf(other));
        assertTrackMinusEq("storedBalance", unit, join.storedBalance());
        assertTrackMinusEq("joinBalance", unit, tether.balanceOf(address(join)));
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
