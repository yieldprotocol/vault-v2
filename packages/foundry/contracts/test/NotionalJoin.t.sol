// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "../test/utils/TestConstants.sol";
import "../test/utils/Mocks.sol";
import "../mocks/ERC20Mock.sol";

//import {IJoin} from "@yield-protocol/vault-interfaces/src/IJoin.sol";
import {Join} from "../Join.sol";
import {NotionalJoin} from "../other/notional/NotionalJoin.sol";
import {FCashMock} from "../other/notional/FCashMock.sol";
import {DAIMock} from "../mocks/DAIMock.sol";

using stdStorage for StdStorage;

abstract contract StateMatured is Test, TestConstants {
    using Mocks for *;

    Join public underlyingJoin; 
    NotionalJoin public njoin; 
    FCashMock public fcash;
    DAIMock public dai;
        
    address user; 
    address deployer;

    // arbitrary values for testing
    uint40 maturity = 1651743369;   // 4/07/2022 23:09:57 GMT
    uint16 currencyId = 2;         
    uint256 fCashId = 4;

    event Redeemed(uint256 fCash, uint256 underlying, uint256 accrual);

    function setUp() public virtual {
        
        //... Users ...
        user = address(1);
        vm.label(user, "user");
        
        deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        vm.label(deployer, "deployer");

        //... Contracts ...
        dai = new DAIMock();
        vm.label(address(dai), "Dai token contract");
        
        fcash = new FCashMock(ERC20Mock(address(dai)), fCashId);
        vm.label(address(fcash), "fCashMock contract");

        //... Deploy Joins and grant access ...
        underlyingJoin = new Join(address(dai));
        vm.label(address(dai), "Dai Join");

        njoin = new NotionalJoin(address(fcash), address(dai), address(underlyingJoin), maturity, currencyId);
        vm.label(address(njoin), "Notional Join");

        njoin.grantRole(NotionalJoin.exit.selector, deployer);
        njoin.grantRole(NotionalJoin.exit.selector, deployer);
        underlyingJoin.grantRole(Join.join.selector, address(njoin));       
        underlyingJoin.grantRole(Join.exit.selector, address(njoin));
        
       // njoin has 10 fCash tokens 
       stdstore
       .target(address(fcash))
       .sig(fcash.balanceOf.selector)
       .with_key(address(njoin))
       .with_key(fCashId)
       .checked_write(10e18);

       // storedBalance = 10 fCash Tokens
        stdstore
       .target(address(njoin))
       .sig(njoin.storedBalance.selector)
       .checked_write(10e18);

       fcash.setAccrual(1e18);  // set fCash == underlying for simplicity

        vm.warp(1651743369 + 100);  // set blocktime to pass maturity
    }  
}

contract StateMaturedTest is StateMatured {
    using Mocks for *;

    // sanity check - maturity
    function testMaturity() public {
        console2.log("fCash tokens are mature");
        assertGe(block.timestamp, maturity);         
    }  
    
    // sanity check - fCash balances
    function testFCashBalance() public {
        console2.log("10 fDai tokens in Notional Join");
        assertTrue(njoin.storedBalance() == 10e18); 
        assertTrue(fcash.balanceOf(address(njoin), fCashId) == 10e18); 
    }
    
    // sanity check - accrual
    function testAccrual() public {
        console2.log("Accrual in Njoin should be 0");
        assertTrue(njoin.accrual() == 0); 
    }
    
    function testRedeem() public {
        console2.log("First exit call should call redeem()");

        vm.expectEmit(true, true, true, false);
        emit Redeemed(0, 10e18, 1e18);

        vm.prank(deployer);
        njoin.exit(user, 5e18);
        
        assertTrue(njoin.accrual() == 1e18);
        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(dai.balanceOf(address(njoin)) == 0); 
                
        assertTrue(dai.balanceOf(user) == 5e18);
        assertTrue(dai.balanceOf(address(underlyingJoin)) == 5e18);
    }
}

abstract contract StateRedeemed is StateMatured {

     function setUp() public override virtual {
        super.setUp();

        // state transition: accrual > 0         
        vm.prank(deployer);
        njoin.exit(user, 5e18);
        assertTrue(njoin.accrual() == 1e18);
    }

}

contract StateRedeemedTest is StateRedeemed {

    function testCannotRedeem() public {
        console2.log("Redeem will revert since accrual > 0");
        
        vm.prank(deployer);
        vm.expectRevert("Already redeemed");
        njoin.redeem();
    }

    function testSubsequentExit() public {
        console2.log("_exitUnderlying executed");

        vm.prank(deployer);
        njoin.exit(user, 5e18);

        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(dai.balanceOf(address(njoin)) == 0); 
        assertTrue(dai.balanceOf(address(underlyingJoin)) == 0);

        assertTrue(dai.balanceOf(address(user)) == 10e18);
        
    }
}
    
    





