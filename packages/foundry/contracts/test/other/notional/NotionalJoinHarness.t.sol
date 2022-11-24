// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "../../../test/utils/TestConstants.sol";

import { ERC1155 } from "../../../other/notional/ERC1155.sol";
import { IWETH9 } from "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import { IERC20 } from "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { IERC20Metadata } from "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import { IJoin } from "../../../interfaces/IJoin.sol";
import { NotionalJoin } from "../../../other/notional/NotionalJoin.sol";
import "./NotionalTypes.sol";

using stdStorage for StdStorage;

abstract contract StateZero is Test, TestConstants {
    using stdStorage for StdStorage;

    event Redeemed(uint256 fCashAmount, uint256 underlying, uint256 accrual);
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);

    address timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    Notional public notional = Notional(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    ERC1155 public fCash = ERC1155(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address public ladle = 0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A;

    // FETH2212: `0xa6624D8CF4A1Ba950d380D1e38A2D5261b711145`
    // FETH2303: `0xa9d104c4e020087944332632a8c5b451885fba4a`

    NotionalJoin public nJoin = NotionalJoin(payable(0xa6624D8CF4A1Ba950d380D1e38A2D5261b711145));
    IJoin public underlyingJoin; 
    IERC20 public underlying;

    uint40 public maturity;  
    uint256 public fCashId;
    uint128 public underlyingUnit;
    uint128 public fCashUnit = 1e8;

    address public me;
    address public user;

    mapping(string => uint256) tracked;


    function track(string memory id, uint256 amount) public {
        tracked[id] = amount;
    }

    function assertTrackPlusEq(string memory id, uint256 plus, uint256 amount) public {
        assertEq(tracked[id] + plus, amount);
    }

    function assertTrackMinusEq(string memory id, uint256 minus, uint256 amount) public {
        assertEq(tracked[id] - minus, amount);
    }

    function assertTrackPlusApproxEqAbs(string memory id, uint256 plus, uint256 amount, uint256 delta) public {
        assertApproxEqAbs(tracked[id] + plus, amount, delta);
    }

    function assertTrackMinusApproxEqAbs(string memory id, uint256 minus, uint256 amount, uint256 delta) public {
        assertApproxEqAbs(tracked[id] - minus, amount, delta);
    }

    function assertApproxGeAbs(uint256 a, uint256 b, uint256 delta) public {
        assertGe(a, b);
        assertApproxEqAbs(a, b, delta);
    }

    function assertTrackPlusApproxGeAbs(string memory id, uint256 plus, uint256 amount, uint256 delta) public {
        assertGe(tracked[id] + plus, amount);
        assertApproxEqAbs(tracked[id] + plus, amount, delta);
    }

    function assertTrackMinusApproxGeAbs(string memory id, uint256 minus, uint256 amount, uint256 delta) public {
        assertGe(tracked[id] - minus, amount);
        assertApproxEqAbs(tracked[id] - minus, amount, delta);
    }

    function cash(IERC20 token, address to, uint256 amount) public {
        uint256 start = token.balanceOf(to);
        deal(address(token), to, start + amount);
    }

    /// @dev Gets fCash of the same denomination as the NotionalJoin
    function getFCash(address to, uint256 amount) public returns (uint256 fCashAmount) {
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

    function setUp() public virtual {
        vm.createSelectFork('tenderly');
        
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
        
        uint256 fCashAmount = getFCash(user, 1000 * underlyingUnit);
        vm.prank(user);
        fCash.setApprovalForAll(address(nJoin), true);
    }
}

contract StateZeroTest is StateZero {
    
    function testHarnessJoin() public {
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
    function setUp() public override virtual {
        super.setUp();
        
        uint128 joinedAmount = fCashUnit;

        vm.prank(user);
        fCash.safeTransferFrom(user, address(nJoin), fCashId, joinedAmount, "");

        vm.prank(ladle);
        nJoin.join(user, joinedAmount);

    }
}


contract StateJoinedTest is StateJoined {
    function testHarnessExit() public {
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
    function setUp() public override virtual {
        super.setUp();
        
        // set blocktime to pass maturity
        vm.warp(maturity + 100); 
    }
}

contract StateMaturedTest is StateMatured {
    // sanity check - maturity
    function testHarnessMaturity() public {
        console2.log("fCash tokens are mature");
        assertGe(block.timestamp, maturity);         
    }  
       
    // sanity check - accrual
    function testHarnessAccrual() public {
        console2.log("Accrual in Njoin should be 0");
        assertTrue(nJoin.accrual() == 0); 
    }

    function testHarnessCannotJoin() public {
        console2.log("Cannot call join() after maturity");
        vm.expectRevert("Only before maturity");
        vm.prank(ladle);
        nJoin.join(user, fCashUnit);
    }

    function testHarnessRedeem() public {
        console2.log("First exit call should call redeem()");
        
        uint128 fCashExited = uint128(fCashUnit);

        assertTrue(nJoin.accrual() == 0);
        assertTrue(underlying.balanceOf(address(nJoin)) == 0);
        uint256 storedBalance = nJoin.storedBalance(); 
        uint256 userBalance = underlying.balanceOf(user);
        
        vm.prank(ladle);
        nJoin.exit(user, fCashExited);
        
        assertGt(nJoin.accrual(), 0);
        assertApproxEqRel(underlying.balanceOf(user), userBalance + fCashExited * underlyingUnit / fCashUnit, 1e17);
        assertApproxEqRel(nJoin.storedBalance(), (storedBalance - fCashExited) * underlyingUnit / fCashUnit, 1e17);
    }
}
// 
// abstract contract StateRedeemed is StateMatured {
// 
//      function setUp() public override virtual {
//         super.setUp();
// 
//         // state transition: accrual > 0         
//         vm.prank(me);
//         nJoin.exit(user, 1e8);
//         assertGt(nJoin.accrual(),0);
//     }
// 
// }
// 
// contract StateRedeemedTest is StateRedeemed {
// 
//     function testHarnessCannotRedeem() public {
//         console2.log("Redeem will revert since accrual > 0");
//         
//         vm.expectRevert("Already redeemed");
//         nJoin.redeem();
//     }
// 
//     function testHarnessSubsequentExit() public {
//         console2.log("_exitUnderlying executed");
//         (address currency, uint16 currencyId) = whichCurrency(fCashId);
//         uint beforeUserBalance = IERC20(currency).balanceOf(user);
//         uint beforeJoinBalance = IERC20(currency).balanceOf(address(underlyingJoin));
//         vm.prank(me);
//         nJoin.exit(user, 1e8);
// 
//         assertTrue(nJoin.storedBalance() == 0); 
//         assertTrue(IERC20(currency).balanceOf(address(nJoin)) == 0); 
//         uint afterUserBalance = IERC20(currency).balanceOf(user);
//         uint afterJoinBalance = IERC20(currency).balanceOf(address(underlyingJoin));
//         if(currencyId == 3){
//             assertApproxEqAbs(afterUserBalance - beforeUserBalance, 1e6, 1e5);
//             assertApproxEqAbs(beforeJoinBalance - afterJoinBalance, 1e6, 1e5);
//         }else{
//             assertApproxEqAbs(afterUserBalance - beforeUserBalance, 1e18, 1e17);
//             assertApproxEqAbs(beforeJoinBalance - afterJoinBalance, 1e18, 1e17);
//         }
//         
//     }
// }
// 