// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "../../../test/utils/TestConstants.sol";
import "../../../test/utils/TestExtensions.sol";

import { ERC1155 } from "../../../other/notional/ERC1155.sol";
import { IWETH9 } from "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";
import { IERC20 } from "@yield-protocol/utils-v2/src/token/IERC20.sol";
import { IERC20Metadata } from "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import { IJoin } from "../../../interfaces/IJoin.sol";
import { NotionalJoin } from "../../../other/notional/NotionalJoin.sol";
import "./NotionalTypes.sol";

using stdStorage for StdStorage;

abstract contract StateZero is Test, TestExtensions, TestConstants {
    using stdStorage for StdStorage;

    event Redeemed(uint256 fCashAmount, uint256 underlying, uint256 accrual);
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);

    address timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    Notional public notional = Notional(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    ERC1155 public fCash = ERC1155(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address public ladle = 0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A;

    // FETH2212: `0xa6624D8CF4A1Ba950d380D1e38A2D5261b711145`
    // FETH2303: `0xa9d104c4e020087944332632a8c5b451885fba4a`
    // FUSDC2303: `0x3FdDa15EccEE67248048a560ab61Dd2CdBDeA5E6`
    // FDAI2303: `0xE6A63e2166fcEeB447BFB1c0f4f398083214b7aB`
    // FUSDC2212: `0xA9078E573EC536c4066A5E89F715553Ed67B13E0`
    // FDAI2212: `0x83e99A843607CfFFC97A3acA15422aC672a463eF`

    NotionalJoin public nJoin;
    IJoin public underlyingJoin; 
    IERC20 public underlying;

    uint40 public maturity;  
    uint256 public fCashId;
    uint128 public underlyingUnit;
    uint128 public fCashUnit = 1e8;

    address public me;
    address public user;

    /// @dev Gets fCash of the same denomination as the NotionalJoin
    function getFCash(uint256 amount) public returns (uint256 fCashAmount) {
        uint16 currencyId_ = uint16(fCashId >> 48);
        cash(IERC20(underlying), address(this), amount);
        IERC20(underlying).approve(address(notional),type(uint).max);

        fCash.setApprovalForAll(address(this), true);

        // Deposit into notional to get the fCash
        BalanceActionWithTrades[]
            memory actions = new BalanceActionWithTrades[](1);
        actions[0] = BalanceActionWithTrades({
            actionType: DepositActionType.DepositUnderlying, // Deposit underlying, not cToken
            currencyId: currencyId_,
            depositActionAmount: amount, // total to invest
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: false, // Return all residual cash to lender
            redeemToUnderlying: false, // Convert cToken to token
            trades: new bytes32[](1)
        });
        // gas: 127997
        bytes32 encodedTrade;
        (fCashAmount, , encodedTrade) = notional.getfCashLendFromDeposit(
            currencyId_,
            amount, // total to invest
            maturity,
            0,
            block.timestamp,
            true
        );

        actions[0].trades[0] = encodedTrade;
        if (currencyId_ == 1) {
            // Converting WETH to ETH since notional accepts ETH
            IWETH9(address(underlying)).withdraw(amount);
            // gas: 302658
            notional.batchBalanceAndTradeAction{value: amount}(
                address(this),
                actions
            );
        } else {
            notional.batchBalanceAndTradeAction(address(this), actions);
        }

        fCash.safeTransferFrom(address(this), user, fCashId, fCashAmount, "");
    }

    receive() external payable {}

    modifier onlyHarness() {
        if (vm.envOr(MOCK, true)) return; // Absence of MOCK makes it default to true
        _;
    }

    function setUpMock() public {}

    function setUpHarness() public {
        // TODO: When using tenderly, guess how to pull the right addresses

        nJoin = NotionalJoin(payable(vm.envAddress("JOIN")));
        fCashId = nJoin.fCashId();
        maturity = nJoin.maturity();
        underlyingJoin = IJoin(nJoin.underlyingJoin());
        underlying = IERC20(underlyingJoin.asset());
        underlyingUnit = uint128(10 ** IERC20Metadata(address(underlying)).decimals());

        //... Users ...
        user = address(1);
        vm.label(user, "user");
        
        //... Contracts ...
        vm.label(address(nJoin), "Notional Join");
        vm.label(address(underlying), "Underlying");
        vm.label(address(underlyingJoin), "Underlying Join");
        vm.label(address(notional), "Notional contract");
        
        vm.prank(user);
        fCash.setApprovalForAll(address(nJoin), true);
    }

    function setUp() public virtual {
        string memory network = vm.envOr(NETWORK, LOCALHOST);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }
}

contract StateZeroTest is StateZero {
    
    function testHarnessJoin() public onlyHarness {
        console2.log("join()");

        uint128 joinedAmount = fCashUnit;

        track("storedBalance", nJoin.storedBalance());

        vm.prank(user);
        fCash.safeTransferFrom(user, address(nJoin), fCashId, joinedAmount, "");
        
        vm.prank(ladle);
        nJoin.join(user, joinedAmount);

        assertTrackPlusEq("storedBalance", joinedAmount, nJoin.storedBalance());
    }
}

// Njoin receives fCash tokens from user
abstract contract StateJoined is StateZero {
    function setUp() public onlyHarness override virtual {
        super.setUp();
        
        uint128 joinedAmount = fCashUnit * 10;

        vm.prank(user);
        fCash.safeTransferFrom(user, address(nJoin), fCashId, joinedAmount, "");

        vm.prank(ladle);
        nJoin.join(user, joinedAmount);

    }
}


contract StateJoinedTest is StateJoined {
    function testHarnessExit() public onlyHarness {
        console2.log("pushes fCash to user");

        uint128 amountExited = fCashUnit;
        
        track("userFCash", fCash.balanceOf(user, fCashId));
        track("storedBalance", nJoin.storedBalance());

        vm.prank(ladle);
        nJoin.exit(user, amountExited);

        assertTrackMinusEq("storedBalance", amountExited, nJoin.storedBalance());
        assertTrackPlusEq("userFCash", amountExited, fCash.balanceOf(user, fCashId));
    }
}

// Njoin holds 2e8 of fCash
abstract contract StateMatured is StateJoined {
    function setUp() public onlyHarness override virtual {
        super.setUp();
        
        // set blocktime to pass maturity
        vm.warp(maturity + 100); 
    }
}

contract StateMaturedTest is StateMatured {
    // sanity check - maturity
    function testHarnessMaturity() public onlyHarness {
        console2.log("fCash tokens are mature");
        assertGe(block.timestamp, maturity);         
    }  
       
    // sanity check - accrual
    function testHarnessAccrual() public onlyHarness {
        console2.log("Accrual in Njoin should be 0");
        assertTrue(nJoin.accrual() == 0); 
    }

    function testHarnessCannotJoin() public onlyHarness {
        console2.log("Cannot call join() after maturity");
        vm.expectRevert("Only before maturity");
        vm.prank(ladle);
        nJoin.join(user, fCashUnit);
    }

    function testHarnessRedeem() public onlyHarness {
        console2.log("First exit call should call redeem()");
        
        uint128 fCashExited = uint128(fCashUnit);

        assertTrue(nJoin.accrual() == 0);
        assertTrue(underlying.balanceOf(address(nJoin)) == 0);
        uint256 storedBalance = nJoin.storedBalance(); 
        uint256 underlyingJoinBalance = underlying.balanceOf(address(underlyingJoin));
        uint256 userBalance = underlying.balanceOf(user);
        uint256 storedBalanceInUnderlying = storedBalance * underlyingUnit / fCashUnit;
        uint256 exitInUnderlying = fCashExited * underlyingUnit / fCashUnit;
        
        vm.prank(ladle);
        nJoin.exit(user, fCashExited);
        
        assertGt(nJoin.accrual(), 0);
        assertApproxEqRel(underlying.balanceOf(user), userBalance + fCashExited * underlyingUnit / fCashUnit, 1e17);
        assertApproxEqRel(underlying.balanceOf(address(underlyingJoin)), underlyingJoinBalance + storedBalanceInUnderlying - exitInUnderlying, 1e17);
        assertEq(nJoin.storedBalance(), 0);
    }
}

abstract contract StateRedeemed is StateMatured {

     function setUp() public override virtual onlyHarness {
        super.setUp();

        nJoin.redeem();
    }

}

contract StateRedeemedTest is StateRedeemed {

    function testHarnessCannotRedeem() public onlyHarness {
        console2.log("Redeem will revert since accrual > 0");
        
        vm.expectRevert("Already redeemed");
        nJoin.redeem();
    }

    function testHarnessSubsequentExit() public onlyHarness {
        console2.log("Regular underlying exit");
        
        uint128 fCashExited = uint128(fCashUnit);

        uint256 underlyingJoinBalance = underlying.balanceOf(address(underlyingJoin));
        uint256 userBalance = underlying.balanceOf(user);
        uint256 exitInUnderlying = fCashExited * underlyingUnit / fCashUnit;
        
        vm.prank(ladle);
        nJoin.exit(user, fCashExited);
        
        assertApproxEqRel(underlying.balanceOf(user), userBalance + fCashExited * underlyingUnit / fCashUnit, 1e17);
        assertApproxEqRel(underlying.balanceOf(address(underlyingJoin)), underlyingJoinBalance - exitInUnderlying, 1e17);
        assertEq(nJoin.storedBalance(), 0);
    }
}
