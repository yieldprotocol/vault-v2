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

/*
    test transfer of underlying to join - thru redeem
    test subsequent transfers

    contracts:
    fCash token -> FCashMock
    fcash join -> NotionalJoin 
    dai Join ->   mock.contract()
    
    test redeem():
    use FCashMock to simulate converting fCash to Dai:
        IBatchAction(asset).batchBalanceAction(address(this), withdrawActions);

    send Dai to desired join: 
            IJoin(underlyingJoin).join(address(this), underlyingBalance.u128());
            it should return `amount`
            test for this
*/

abstract contract StateMatured is Test, TestConstants {
    using Mocks for *;

    NotionalJoin public njoin; 
    FCashMock public fcash;
    DAIMock public dai;

    IJoin internal underlyingJoin;

    // arbitrary values for testing
    uint40 maturity = 1651743369;   
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

       fcash.setAccrual(10**18);  // set fCash == underlying for simplicity

    }  
}

contract StateMaturedTest is StateMatured {
    using Mocks for *;

    // sanity check
    function testMaturity() public {
        console2.log("fCash tokens are mature");
        skip(3600);
        assertGe(block.timestamp, maturity);         
    }  

    function testFCashBalance() public {
        console2.log("10 fDai tokens in Notional Join");
        assertTrue(njoin.storedBalance() == 10e18); 
        assertTrue(fcash.balanceOf(address(njoin), fCashId) == 10e18); 
    }

    function testRedeem() public {
        console2.log("Call redeem from Njoin");

        // mock join fn call, returns amount 
        underlyingJoin.join.mock(address(njoin), 10e18, 10e18);
        //underlyingJoin.join.verify(address(njoin), 10**18);

        njoin.redeem();

        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(dai.balanceOf(address(njoin)) == 0); 
        assertTrue(dai.balanceOf(address(underlyingJoin)) == 10e18);

        //vm.expectEmit(true, true, true);
        //emit Redeemed(10e18, 10e18, 10e18);
    }
}



