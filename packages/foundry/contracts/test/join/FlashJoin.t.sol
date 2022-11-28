// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { TestExtensions } from "../TestExtensions.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { IERC3156FlashBorrower, IERC3156FlashLender, Join, FlashJoin } from "../../FlashJoin.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { FlashBorrower } from "../../mocks/FlashBorrower.sol";

using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions, TestConstants {

    FlashJoin public join; 
    FlashBorrower borrower;
    IERC20 public token;
    uint128 public unit;
    IERC20 public otherToken;
    uint128 public otherUnit;
        
    address user;
    address other;
    address ladle;
    address timelock;
    address me;

    function setUpMock() public {
        ladle = address(3);
        timelock = address(4);

        //... Contracts ...
        token = IERC20(address(new ERC20Mock("", "")));
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());

        otherToken = IERC20(address(new ERC20Mock("", "")));
        otherUnit = uint128(10 ** ERC20Mock(address(otherToken)).decimals());

        //... Deploy Joins and grant access ...
        join = new FlashJoin(address(token));

        //... Permissions ...
        join.grantRole(Join.join.selector, ladle);
        join.grantRole(Join.exit.selector, ladle);
        join.grantRole(Join.retrieve.selector, ladle);
        join.grantRole(FlashJoin.setFlashFeeFactor.selector, timelock);
    }

    function setUpHarness(string memory network) public {
        ladle = addresses[network][LADLE];
        timelock = addresses[network][TIMELOCK];

        join = FlashJoin(vm.envAddress("JOIN"));
        token = IERC20(join.asset());
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());

        otherToken = IERC20(address(new ERC20Mock("", "")));
        otherUnit = uint128(10 ** ERC20Mock(address(otherToken)).decimals());

        // Grant timelock permissions to set the flash fee factor.
        vm.prank(timelock);
        join.grantRole(FlashJoin.setFlashFeeFactor.selector, timelock);
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

        //... FlashBorrower
        borrower = new FlashBorrower(IERC3156FlashLender(address(join)));

        vm.label(ladle, "ladle");
        vm.label(user, "user");
        vm.label(other, "other");
        vm.label(me, "me");
        vm.label(address(token), "token");
        vm.label(address(otherToken), "otherToken");
        vm.label(address(join), "join");

        cash(token, user, 100 * unit);

        // If there are any unclaimed assets in the FlashJoin, join them.
        uint128 unclaimedTokens = uint128(token.balanceOf(address(join)) - join.storedBalance());
        vm.prank(ladle);
        join.join(address(join), unclaimedTokens);

        // Enable flash loans and set them to zero
        vm.prank(timelock);
        join.setFlashFeeFactor(0);

        // Make sure that the Join has enough funds to run the tests
        uint128 joinTopUp = uint128(100 * unit - join.storedBalance());
        cash(token, address(join), joinTopUp);
        vm.prank(ladle);
        join.join(address(join), joinTopUp);
    }  
}

contract ZeroFeeTest is Deployed {

    function testNeedsApproveRepayment() public {
        vm.expectRevert("ERC20: Insufficient approval");
        vm.prank(user);
        join.flashLoan(IERC3156FlashBorrower(address(borrower)), address(token), WAD, abi.encode(FlashBorrower.Action.NORMAL));
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
