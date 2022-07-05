// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "../test/utils/TestConstants.sol";
import "../test/utils/Mocks.sol";
import "../mocks/ERC20Mock.sol";

import {IJoin} from "@yield-protocol/vault-interfaces/src/IJoin.sol";
import {NotionalJoin} from "../other/notional/NotionalJoin.sol";
import {FCashMock} from "../other/notional/FCashMock.sol";
import {DAIMock} from "../mocks/DAIMock.sol";

using stdStorage for StdStorage;

abstract contract StateMatured is Test, TestConstants {
    using Mocks for *;

    NotionalJoin public njoin; 
    FCashMock public fcash;
    DAIMock public dai;

    IJoin internal underlyingJoin;
    
    address user; 
    address deployer;

    // arbitrary values for testing
    uint40 maturity = 1651743369;   // 4/07/2022 23:09:57 GMT
    uint16 currencyId = 2;         
    uint256 fCashId = 4;

    event Redeemed(uint256 fCash, uint256 underlying, uint256 accrual);

    function setUp() public virtual {

        dai = new DAIMock();
        vm.label(address(dai), "dai contract");
        
        // Create mock of underlying join
        underlyingJoin = IJoin(Mocks.mock("Join"));

        fcash = new FCashMock(ERC20Mock(address(dai)), fCashId);
        vm.label(address(fcash), "fCashMock contract");

        njoin = new NotionalJoin(address(fcash), address(dai), address(underlyingJoin), maturity, currencyId);
        vm.label(address(njoin), "Notional Join");
        
        user = address(1);
        vm.label(user, "user");

        deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        vm.label(deployer, "deployer");

        //grant access permissions to deployer
        njoin.grantRole(NotionalJoin.exit.selector, deployer);


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
    
    // test will fail on .join() call to underlying join in redeem()
    function testCannotExitUnderlyingBeforeReedem() public {
        console2.log("First exit call should not bypass redeem()");
        
        // mock for _exitUnderlying()
        underlyingJoin.exit.mock(user, 10e18, 10e18);

        vm.expectRevert(bytes("Not mocked!"));
        vm.prank(deployer);
        njoin.exit(user, 10e18);

    }

    function testRedeem() public {
        console2.log("First exit call should call redeem()");

        // mock for redeem()
        underlyingJoin.join.mock(address(njoin), 10e18, 10e18);
        // mock for _exitUnderlying()
        underlyingJoin.exit.mock(user, 10e18, 10e18);

        underlyingJoin.join.verify(address(njoin), 10e18);
        underlyingJoin.exit.verify(user, 10e18);
        
        vm.expectEmit(true, true, true, false);
        emit Redeemed(0, 10e18, 1e18);

        vm.prank(deployer);
        njoin.exit(user, 10e18);

        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(dai.balanceOf(address(njoin)) == 0); 
        
        assertTrue(njoin.accrual() == 1e18);
        assertTrue(dai.balanceOf(address(underlyingJoin)) == 10e18);
    }
}

abstract contract StateRedeemed is StateMatured {
    using Mocks for *;

     function setUp() public override virtual {
        super.setUp();

        // state transition: accrual > 0
        underlyingJoin.join.mock(address(njoin), 10e18, 10e18);
        underlyingJoin.exit.mock(user, 10e18, 10e18);
          
        vm.prank(deployer);
        njoin.exit(user, 10e18);

        assertTrue(njoin.accrual() == 1e18);
    }

}

contract StateRedeemedTest is StateRedeemed {
    using Mocks for *;

    function testCannotRedeem() public {
        console2.log("Redeem will revert since accrual > 0");
        
        vm.prank(deployer);
        vm.expectRevert("Already redeemed");
        njoin.redeem();
    }

    function testSubsequentExit() public {
        console2.log("Redeem should be skipped, _exitUnderlying executed");

        underlyingJoin.exit.mock(user, 10e18, 10e18);
        underlyingJoin.exit.verify(user, 10e18);

        vm.prank(deployer);
        njoin.exit(user, 10e18);

        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(dai.balanceOf(address(njoin)) == 0); 
        assertTrue(dai.balanceOf(address(underlyingJoin)) == 10e18);
    }
}
    
    





