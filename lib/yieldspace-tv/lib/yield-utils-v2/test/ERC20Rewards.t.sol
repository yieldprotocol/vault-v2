// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/token/IERC20.sol";
import { ERC20Mock } from "../src/mocks/ERC20Mock.sol";
import { ERC20Rewards, ERC20RewardsMock } from "../src/mocks/ERC20RewardsMock.sol";
import { TestExtensions } from "./utils/TestExtensions.sol";
import { TestConstants } from "./utils/TestConstants.sol";


using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions, TestConstants {

    event RewardsTokenSet(IERC20 token);
    event RewardsSet(uint32 start, uint32 end, uint256 rate);
    event RewardsPerTokenUpdated(uint256 accumulated);
    event UserRewardsUpdated(address user, uint256 userRewards, uint256 paidRewardPerToken);
    event Claimed(address user, address receiver, uint256 claimed);

    ERC20RewardsMock public vault;
    uint256 public vaultUnit;
    IERC20 public rewards;
    uint256 public rewardsUnit;
    uint256 totalRewards = 10 * WAD;
    uint256 length = 1000000;


    address user;
    address other;
    address admin;
    address me;

    function setUpMock() public {
        admin = address(3);

        vault = new ERC20RewardsMock("Incentivized Vault", "VLT", 18);
        vaultUnit = 10 ** ERC20Mock(address(vault)).decimals();
        rewards = IERC20(address(new ERC20Mock("Rewards Token", "REW")));
        rewardsUnit = 10 ** ERC20Mock(address(rewards)).decimals();

        vault.grantRole(ERC20Rewards.setRewardsToken.selector, admin);
        vault.grantRole(ERC20Rewards.setRewards.selector, admin);
    }

    function setUpHarness(string memory network) public {
        setUpMock(); // TODO: Not sure how to setup a test harness if ERC20Rewards doesn't have public methods for `mint` and `burn`.
    }

    function setUp() public virtual {
        string memory network = vm.envString(NETWORK);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envBool(MOCK)) setUpMock();
        else setUpHarness(network);

        //... Users ...
        user = address(1);
        other = address(2);
        me = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

        vm.label(user, "user");
        vm.label(other, "other");
        vm.label(admin, "admin");
        vm.label(me, "me");
        vm.label(address(vault), "vault");
        vm.label(address(rewards), "rewards");
    }
}

contract DeployedTest is Deployed {

    function testSetRewardsToken(IERC20 token) public {
        vm.expectEmit(true, false, false, false);
        emit RewardsTokenSet(token);

        vm.prank(admin);
        vault.setRewardsToken(token);

        assertEq(address(vault.rewardsToken()), address(token));
    }
}

abstract contract WithRewardsToken is Deployed {
    function setUp() public override virtual {
        super.setUp();

        vm.prank(admin);
        vault.setRewardsToken(rewards);
    }
}


contract WithRewardsTokenTest is WithRewardsToken {

    function testDontResetRewardsToken(address token) public {
        vm.expectRevert(bytes("Rewards token already set"));

        vm.prank(admin);
        vault.setRewardsToken(IERC20(token));
    }

    function testStartBeforeEnd(uint32 start, uint32 end) public {
        end = uint32(bound(end, block.timestamp, type(uint32).max - 1));
        start = uint32(bound(start, end + 1, type(uint32).max));
        vm.expectRevert(bytes("Incorrect input"));
        vm.prank(admin);
        vault.setRewards(start, end, 1);
    }

    function testSetRewards(uint32 start, uint32 end, uint96 rate) public {
        end = uint32(bound(end, block.timestamp + 1, type(uint32).max));
        start = uint32(bound(start, block.timestamp, end - 1));

        vm.expectEmit(true, false, false, false);
        emit RewardsSet(start, end, rate);

        vm.prank(admin);
        vault.setRewards(start, end, rate);

        (uint32 start_, uint32 end_) = vault.rewardsPeriod();
        (,, uint96 rate_) = vault.rewardsPerToken();

        assertEq(start_, start);
        assertEq(end_, end);
        assertEq(rate_, rate);
    }
}

abstract contract WithProgram is WithRewardsToken {
    function setUp() public override virtual {
        super.setUp();

        uint256 start = block.timestamp + 1000000;
        uint256 end = start + length;
        uint256 rate = totalRewards / length;

        vm.startPrank(admin);
        vault.setRewards(uint32(start), uint32(end), uint96(rate));
        vm.stopPrank();

        cash(rewards, address(vault), totalRewards); // Rewards to be distributed
        vault.mint(user, 0.2e18); // So that total supply is not zero and ERC20Rewards:L118 is not skipped later
    }
}

contract WithProgramTest is WithProgram {

    function testProgramChange(uint32 start, uint32 end, uint96 rate) public {
        end = uint32(bound(end, block.timestamp + 1, type(uint32).max));
        start = uint32(bound(start, block.timestamp, end - 1));

        vm.expectEmit(true, false, false, false);
        emit RewardsSet(start, end, rate);

        vm.prank(admin);
        vault.setRewards(start, end, rate);
    }

    function testDoesntUpdateRewardsPerToken() public {
        vault.mint(user, WAD);
        (uint128 accumulated,,) = vault.rewardsPerToken();
        assertEq(accumulated, 0);
    }

    function testDoesntUpdateUserRewards() public {
        vault.mint(user, WAD);
        (uint128 accumulated,) = vault.rewards(user);
        assertEq(accumulated, 0);
    }
}

abstract contract DuringProgram is WithProgram {
    function setUp() public override virtual {
        super.setUp();
        vault.mint(user, 9.8e18); // increase total supply to 10 WAD

        (uint256 start,) = vault.rewardsPeriod();

        vm.warp(start);
    }
}

contract DuringProgramTest is DuringProgram {

    function dontChangeProgram(uint32 start, uint32 end, uint96 rate) public {
        end = uint32(bound(end, block.timestamp + 1, type(uint32).max));
        start = uint32(bound(start, block.timestamp, end - 1));

        vm.expectRevert(bytes("Ongoing program"));
        vm.prank(admin);
        vault.setRewards(start, end, rate);
    }

    function testUpdatesRewardsPerTokenOnMint(uint32 elapsed) public {
        uint256 totalSupply = vault.totalSupply();
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 0, end - start));
        vm.warp(start + elapsed);
        vault.mint(user, 1);

        (uint128 accumulated, uint32 lastUpdated, uint96 rate) = vault.rewardsPerToken();
        assertEq(lastUpdated, block.timestamp);
        assertEq(accumulated, uint256(rate) * elapsed * 1e18 / totalSupply); // accumulated is stored scaled up by 1e18
    }

    function testUpdatesRewardsPerTokenOnBurn(uint32 elapsed) public {
        uint256 totalSupply = vault.totalSupply();
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 0, end - start));
        vm.warp(start + elapsed);
        vault.burn(user, 1);

        (uint128 accumulated, uint32 lastUpdated, uint96 rate) = vault.rewardsPerToken();
        assertEq(lastUpdated, block.timestamp);
        assertEq(accumulated, uint256(rate) * elapsed * 1e18 / totalSupply); // accumulated is stored scaled up by 1e18
    }

    function testUpdatesRewardsPerTokenOnTransfer(uint32 elapsed) public {
        uint256 totalSupply = vault.totalSupply();
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 0, end - start));
        vm.warp(start + elapsed);
        vm.prank(user);
        vault.transfer(other, 1);

        (uint128 accumulated, uint32 lastUpdated, uint96 rate) = vault.rewardsPerToken();
        assertEq(lastUpdated, block.timestamp);
        assertEq(accumulated, uint256(rate) * elapsed * 1e18 / totalSupply); // accumulated is stored scaled up by 1e18
    }

    function testUpdatesUserRewardsOnMint(uint32 elapsed, uint32 elapseAgain, uint128 mintAmount) public {
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 0, end - start));

        vm.warp(start + elapsed);
        vault.mint(user, mintAmount);
        (uint128 accumulatedUserStart, uint128 accumulatedCheckpoint) = vault.rewards(user);
        (uint128 accumulatedPerToken,,) = vault.rewardsPerToken();
        assertEq(accumulatedCheckpoint, accumulatedPerToken);

        elapseAgain = uint32(bound(elapseAgain, 0, end - (start + elapsed)));
        vm.warp(start + elapsed + elapseAgain);
        uint256 userBalance = vault.balanceOf(user);
        vault.mint(user, mintAmount);
        (uint128 accumulatedPerTokenNow,,) = vault.rewardsPerToken();
        (uint128 accumulatedUser,) = vault.rewards(user);
        assertEq(accumulatedUser, accumulatedUserStart + userBalance * (accumulatedPerTokenNow - accumulatedPerToken) / 1e18);
    }

    function testUpdatesUserRewardsOnBurn(uint32 elapsed, uint32 elapseAgain, uint128 burnAmount) public {
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 0, end - start));
        uint256 userBalance = vault.balanceOf(user);
        assertGt(userBalance, 0);
        burnAmount = uint128(bound(burnAmount, 0, userBalance)) / 2;

        vm.warp(start + elapsed);
        vault.burn(user, burnAmount);
        (uint128 accumulatedUserStart, uint128 accumulatedCheckpoint) = vault.rewards(user);
        (uint128 accumulatedPerToken,,) = vault.rewardsPerToken();
        assertEq(accumulatedCheckpoint, accumulatedPerToken);

        elapseAgain = uint32(bound(elapseAgain, 0, end - (start + elapsed)));
        vm.warp(start + elapsed + elapseAgain);
        userBalance = vault.balanceOf(user);
        vault.burn(user, burnAmount);
        (uint128 accumulatedPerTokenNow,,) = vault.rewardsPerToken();
        (uint128 accumulatedUser,) = vault.rewards(user);
        assertEq(accumulatedUser, accumulatedUserStart + userBalance * (accumulatedPerTokenNow - accumulatedPerToken) / 1e18);
    }

    function testUpdatesUserRewardsOnTransfer(uint32 elapsed, uint32 elapseAgain, uint128 transferAmount) public {
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 0, end - start));
        uint256 userBalance = vault.balanceOf(user);
        assertGt(userBalance, 0);
        transferAmount = uint128(bound(transferAmount, 0, userBalance));

        vm.warp(start + elapsed);
        vm.prank(user);
        vault.transfer(other, transferAmount);
        (uint128 accumulatedUserStart, uint128 accumulatedCheckpointUser) = vault.rewards(user);
        (uint128 accumulatedOtherStart, uint128 accumulatedCheckpointOther) = vault.rewards(other);
        (uint128 accumulatedPerToken,,) = vault.rewardsPerToken();
        assertEq(accumulatedCheckpointUser, accumulatedPerToken);
        assertEq(accumulatedCheckpointOther, accumulatedPerToken);

        elapseAgain = uint32(bound(elapseAgain, 0, end - (start + elapsed)));
        vm.warp(start + elapsed + elapseAgain);
        userBalance = vault.balanceOf(user);
        uint256 otherBalance = vault.balanceOf(other);
        vm.prank(other);
        vault.transfer(user, transferAmount);
        (uint128 accumulatedPerTokenNow,,) = vault.rewardsPerToken();
        (uint128 accumulatedUser,) = vault.rewards(user);
        (uint128 accumulatedOther,) = vault.rewards(other);
        assertEq(accumulatedUser, accumulatedUserStart + userBalance * (accumulatedPerTokenNow - accumulatedPerToken) / 1e18);
        assertEq(accumulatedOther, accumulatedOtherStart + otherBalance * (accumulatedPerTokenNow - accumulatedPerToken) / 1e18);
    }

    function testClaim() public {
        (uint32 start,) = vault.rewardsPeriod();
        uint256 elapsed = length / 10; //  100_000
        vm.warp(start + elapsed);

        (uint128 accumulatedUser,) = vault.rewards(user);
        assertEq(accumulatedUser, 0);

        track("otherRewardsBalance", rewards.balanceOf(other));

        uint256 calculatedRewards = totalRewards * elapsed / length;

        vm.expectEmit(true, true, false, false);
        emit Claimed(user, other, calculatedRewards);
        vm.prank(user);
        vault.claim(other);
        (uint128 accumulatedPerTokenNow,,) = vault.rewardsPerToken();

        uint256 expectedRewards = uint256(accumulatedPerTokenNow) * vault.totalSupply() / 1e18;
        assertEq(expectedRewards, calculatedRewards);

        assertTrackPlusEq("otherRewardsBalance", expectedRewards, rewards.balanceOf(other));
        assertEq(expectedRewards, WAD);
    }

    function testClaim(uint32 elapsed) public {
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 1, end - start));
        vm.warp(start + elapsed);

        (uint128 accumulatedUser,) = vault.rewards(user);
        assertEq(accumulatedUser, 0);

        track("otherRewardsBalance", rewards.balanceOf(other));

        uint256 calculatedRewards = totalRewards * elapsed / length;

        vm.expectEmit(true, true, false, false);
        emit Claimed(user, other, calculatedRewards);
        vm.prank(user);
        vault.claim(other);
        (uint128 accumulatedPerTokenNow,,) = vault.rewardsPerToken();

        uint256 expectedRewards = uint256(accumulatedPerTokenNow) * vault.totalSupply() / 1e18;
        assertEq(expectedRewards, calculatedRewards);

        assertTrackPlusEq("otherRewardsBalance", expectedRewards, rewards.balanceOf(other));
    }


    function testRemit(uint32 elapsed) public {
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        elapsed = uint32(bound(elapsed, 1, end - start));
        vm.warp(start + elapsed);

        (uint128 accumulatedUser,) = vault.rewards(user);
        assertEq(accumulatedUser, 0);

        track("userRewardsBalance", rewards.balanceOf(user));

        uint256 calculatedRewards = totalRewards * elapsed / length;

        vm.expectEmit(true, true, false, false);
        emit Claimed(user, user, calculatedRewards);
        vm.prank(other);
        vault.remit(user);
        (uint128 accumulatedPerTokenNow,,) = vault.rewardsPerToken();

        uint256 expectedRewards = uint256(accumulatedPerTokenNow) * vault.totalSupply() / 1e18;
        assertEq(expectedRewards, calculatedRewards);

        assertTrackPlusEq("userRewardsBalance", expectedRewards, rewards.balanceOf(user));
    }
}

abstract contract AfterProgramEnd is WithProgram {
    function setUp() public override virtual {
        super.setUp();

        (, uint256 end) = vault.rewardsPeriod();

        vm.warp(end + 1);
    }
}

contract AfterProgramEndTest is AfterProgramEnd {

    function testSetNewRewards(uint32 start, uint32 end, uint96 rate) public {
        // Collect data from previous period to make sure per token rewards are updated
        (uint32 previousStart, uint32 previousEnd) = vault.rewardsPeriod();
        (,, uint96 previousRate) = vault.rewardsPerToken();
        vm.expectEmit(true, false, false, false);
        emit RewardsPerTokenUpdated((previousEnd - previousStart) * previousRate);

        // Setup a new rewards period
        end = uint32(bound(end, block.timestamp + 1, type(uint32).max));
        start = uint32(bound(start, block.timestamp, end - 1));
        vm.expectEmit(true, true, true, false);
        emit RewardsSet(start, end, rate);

        vm.prank(admin);
        vault.setRewards(start, end, rate);

        (uint32 start_, uint32 end_) = vault.rewardsPeriod();
        (,, uint96 rate_) = vault.rewardsPerToken();

        assertEq(start_, start);
        assertEq(end_, end);
        assertEq(rate_, rate);
    }

    function testAccumulateNoMore() public {
        (,, uint96 rate) = vault.rewardsPerToken();
        (uint32 start, uint32 end) = vault.rewardsPeriod();
        uint256 expectedAccumulated = 1e18 * ((end - start) * rate / vault.totalSupply());
        vm.warp(end + 10);

        vault.mint(user, WAD);

        (uint128 globalAccumulated,,) = vault.rewardsPerToken();
        (, uint128 userAccumulated) = vault.rewards(user);

        assertEq(globalAccumulated, expectedAccumulated);
        assertEq(userAccumulated, expectedAccumulated);
    }
}