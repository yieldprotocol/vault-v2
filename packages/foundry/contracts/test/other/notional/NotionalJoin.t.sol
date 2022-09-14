// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "../../../test/utils/TestConstants.sol";
import "../../../test/utils/Mocks.sol";
import "../../../mocks/ERC20Mock.sol";

//import {IJoin} from "@yield-protocol/vault-interfaces/src/IJoin.sol";
import {Join} from "../../../Join.sol";
import {NotionalJoin} from "../../../other/notional/NotionalJoin.sol";
import {FCashMock} from "../../../other/notional/FCashMock.sol";
import {DAIMock} from "../../../mocks/DAIMock.sol";

using stdStorage for StdStorage;

abstract contract StateZero is Test, TestConstants {
    using Mocks for *;

    Join public underlyingJoin; 
    NotionalJoin public njoin; 
    FCashMock public fcash;
    DAIMock public dai;
        
    address user; 
    address deployer;
    uint256 fCashTokens;

    uint40 maturity;  
    uint16 currencyId;         
    uint256 fCashId;

    event Redeemed(uint256 fCash, uint256 underlying, uint256 accrual);
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);

    function setUp() public virtual {
        
        // arbitrary values for testing
        fCashTokens = 10e18;
        maturity = 1671840000;  // 4/07/2022 23:09:57 GMT
        currencyId = 2;         
        fCashId = 563377944461313;

        //... Users ...
        user = address(1);
        vm.label(user, "user");
        
        deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        vm.label(deployer, "deployer");

        //... Contracts ...
        dai = new DAIMock();
        vm.label(address(dai), "Dai token contract");
        
        fcash = new FCashMock(ERC20Mock(address(dai)), fCashId);
        fcash.setAccrual(1e18);  // set fCash == underlying for simplicity
        vm.label(address(fcash), "fCashMock contract");

        //... Deploy Joins and grant access ...
        underlyingJoin = new Join(address(dai));
        vm.label(address(dai), "Dai Join");

        njoin = new NotionalJoin(address(fcash), address(dai), address(underlyingJoin), maturity, currencyId);
        vm.label(address(njoin), "Notional Join");

        //... Permissions ...
        njoin.grantRole(NotionalJoin.join.selector, deployer);
        njoin.grantRole(NotionalJoin.exit.selector, deployer);
        njoin.grantRole(NotionalJoin.retrieve.selector, deployer);
        njoin.grantRole(NotionalJoin.retrieveERC1155.selector, deployer);

        underlyingJoin.grantRole(Join.join.selector, address(njoin));       
        underlyingJoin.grantRole(Join.exit.selector, address(njoin));
        

        fcash.mint(user, fCashId, 10e18, "");
        vm.prank(user);
        fcash.setApprovalForAll(address(njoin), true);
        
    }  
}

contract StateZeroTest is StateZero {
    
    function testJoin() public {
        console2.log("join pulls fCash from user");

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(njoin), user, address(njoin), fCashId, 1e18);

        njoin.join(user, 1e18);

        assertTrue(njoin.storedBalance() ==  1e18);
        assertTrue(fcash.balanceOf(user, fCashId) ==  fCashTokens - 1e18);
    }
}

// Njoin receives fcash tokens from user
abstract contract StateJoined is StateZero {
    function setUp() public override virtual {
        super.setUp();

        njoin.join(user, 2e18);

    }
}

// Njoin has 2e18 fCash | storedBalance = 2e18
contract StateJoinedTest is StateJoined {

    function testAcceptSurplus() public {
        console2.log("accepts surplus as a transfer");
        
        //surplus 
        vm.prank(user);
        fcash.safeTransferFrom(user, address(njoin), fCashId, 1e18, "");

        // no TransferSingle event emitted
        njoin.join(user, 1e18);
        
        assertTrue(njoin.storedBalance() ==  3e18);
        assertTrue(fcash.balanceOf(user, fCashId) ==  fCashTokens - 3e18);

    }

    function testSurplusRegistered() public {
        console2.log("combines surplus and fCashs pulled from the user");

        // surplus of 1e18
        vm.prank(user);
        fcash.safeTransferFrom(user, address(njoin), fCashId, 1e18, "");

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(njoin), user, address(njoin), fCashId, 1e18);
        
        // 1e18 transferred from user | 1e18 taken from surplus
        njoin.join(user, 2e18);

        assertTrue(njoin.storedBalance() ==  4e18);
        assertTrue(fcash.balanceOf(user, fCashId) ==  fCashTokens - 4e18);
    }
}

abstract contract StatePositiveStoredBalance is StateJoined {
    function setUp() public override virtual {
        super.setUp(); 
    }
}

// Njoin holds 2e18 of fCash
contract StatePositiveStoredBalanceTest is StatePositiveStoredBalance {
    function testExit() public {
        console2.log("pushes fCash to user");

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(njoin), address(njoin), user, fCashId, 1e18);

        njoin.exit(user, 1e18);

        assertTrue(njoin.storedBalance() ==  1e18);
        assertTrue(fcash.balanceOf(user, fCashId) ==  fCashTokens - 1e18);

    }
}

// Njoin holds 2e18 of fCash
abstract contract StateMatured is StatePositiveStoredBalance {
    function setUp() public override virtual {
        super.setUp();
        
        // set blocktime to pass maturity
        vm.warp(maturity + 100); 
    }
}

contract StateMaturedTest is StateMatured {
    using Mocks for *;

    // sanity check - maturity
    function testMaturity() public {
        console2.log("fCash tokens are mature");
        assertGe(block.timestamp, maturity);         
    }  
       
    // sanity check - accrual
    function testAccrual() public {
        console2.log("Accrual in Njoin should be 0");
        assertTrue(njoin.accrual() == 0); 
    }

    function testCannotJoin() public {
        console2.log("Cannot call join() after maturity");

        vm.expectRevert("Only before maturity");
        njoin.join(user, 1e18);
    }

    function testRedeem() public {
        console2.log("First exit call should call redeem()");

        vm.expectEmit(true, true, true, false);
        emit Redeemed(0, 10e18, 1e18);

        njoin.exit(user, 1e18);
        
        assertTrue(njoin.accrual() == 1e18);
        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(dai.balanceOf(address(njoin)) == 0); 
        
        // 1 dai to user on redemption, 1 dai remains in underlyingJoin
        assertTrue(dai.balanceOf(user) == 1e18);
        assertTrue(dai.balanceOf(address(underlyingJoin)) == 1e18);
    }
}

abstract contract StateRedeemed is StateMatured {

     function setUp() public override virtual {
        super.setUp();

        // state transition: accrual > 0         
        vm.prank(deployer);
        njoin.exit(user, 1e18);
        assertTrue(njoin.accrual() == 1e18);
    }

}

contract StateRedeemedTest is StateRedeemed {

    function testCannotRedeem() public {
        console2.log("Redeem will revert since accrual > 0");
        
        vm.expectRevert("Already redeemed");
        njoin.redeem();
    }

    function testSubsequentExit() public {
        console2.log("_exitUnderlying executed");

        vm.prank(deployer);
        njoin.exit(user, 1e18);

        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(dai.balanceOf(address(njoin)) == 0); 
        assertTrue(dai.balanceOf(address(underlyingJoin)) == 0);

        assertTrue(dai.balanceOf(address(user)) == 2e18);
        
    }
}

    
    





