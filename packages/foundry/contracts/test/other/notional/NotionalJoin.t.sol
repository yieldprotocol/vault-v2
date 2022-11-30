// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console2.sol";

import "../../../test/utils/TestConstants.sol";
import "../../../test/utils/Mocks.sol";
import "../../../mocks/ERC20Mock.sol";

import { ILadle } from "../../../interfaces/ILadle.sol";
import { Join } from "../../../Join.sol";
import { NotionalJoin } from "../../../other/notional/NotionalJoin.sol";
import { ERC1155 } from "../../../other/notional/ERC1155.sol";
import { IWETH9 } from "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "./NotionalTypes.sol";
using stdStorage for StdStorage;

abstract contract StateZero is Test, TestConstants {
    using stdStorage for StdStorage;

    Join public underlyingJoin; 
    NotionalJoin public njoin; 
    address timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    Notional public notional = Notional(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    ERC1155 public fCash = ERC1155(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    bytes6 public wethId = 0x303000000000;
    bytes6 public daiId = 0x303100000000;
    bytes6 public usdcId = 0x303200000000;
    bytes6 public underlyingId;
    IWETH9 public weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public underlying;

    address me;
    address user; 
    uint256 fCashTokens;

    uint40 maturity;  
    uint16 currencyId;         
    uint256 fCashId;

    event Redeemed(uint256 fCashAmount, uint256 underlying, uint256 accrual);
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);

    function cash(IERC20 token, address user, uint256 amount) public {
        uint256 start = token.balanceOf(user);
        deal(address(token), user, start + amount);
    }

    function whichCurrency(uint256 id) internal returns (address currency,uint16 currencyId_){
        currencyId_ = uint16(id >> 48);
        if (currencyId_ == 1) currency = address(weth);
        else if (currencyId_ == 2) currency = address(dai);
        else if (currencyId_ == 3) currency = address(usdc);
    }

    function getFCash(address to, uint256 id, uint256 amount) public returns (uint256 fCashAmount) {
        (address currency, uint16 currencyId_) = whichCurrency(id);
        cash(IERC20(currency), address(this), amount);
        IERC20(currency).approve(address(notional),type(uint).max);

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
            weth.withdraw(amount);
            // gas: 302658
            notional.batchBalanceAndTradeAction{value: amount}(
                address(this),
                actions
            );
        } else {
            notional.batchBalanceAndTradeAction(address(this), actions);
        }

        fCash.safeTransferFrom(address(this),user,fCashId,fCashAmount,"");
    }

    function setUp() public virtual {
        vm.createSelectFork(MAINNET, 16017869);
        
        // arbitrary values for testing
        fCashTokens = 10e18;
        maturity = 1679616000;  // EODEC
        currencyId = 3;
        underlyingId = usdcId;


        //... Users ...
        me = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        user = address(1);
        vm.label(user, "me");
        vm.label(user, "user");
        
        //... Contracts ...
        vm.label(address(weth), "Weth token contract");
        vm.label(address(dai), "Dai token contract");
        vm.label(address(usdc), "USDC token contract");
        vm.label(address(notional), "Notional contract");

        vm.startPrank(timelock);

        //... Deploy Joins and grant access ...
        underlyingJoin = Join(address(ladle.joins(underlyingId)));
        underlying = IERC20(underlyingJoin.asset());
        vm.label(address(underlyingJoin), "Underlying Join");

        njoin = new NotionalJoin(address(fCash), address(underlyingJoin.asset()), address(underlyingJoin), maturity, currencyId);
        vm.label(address(njoin), "Notional Join");

        //... Permissions ...
        njoin.grantRole(NotionalJoin.join.selector, me);
        njoin.grantRole(NotionalJoin.exit.selector, me);
        njoin.grantRole(NotionalJoin.retrieve.selector, me);
        njoin.grantRole(NotionalJoin.retrieveERC1155.selector, me);

        underlyingJoin.grantRole(Join.join.selector, address(njoin));       
        underlyingJoin.grantRole(Join.exit.selector, address(njoin));

        vm.stopPrank();
        
        fCashId = encodeAssetId(currencyId, maturity, 1);
        uint256 amount = currencyId == 3 ? 10e8 : 10e18;
        uint256 fCashAmount = getFCash(user, fCashId, amount);
        vm.prank(user);
        fCash.setApprovalForAll(address(njoin), true);
    }

    function encodeAssetId(
        uint256 currencyId,
        uint256 maturity,
        uint256 assetType
    ) internal pure returns (uint256) {
        return
            uint256(
                (bytes32(uint256(uint16(currencyId))) << 48) |
                    (bytes32(uint256(uint40(maturity))) << 8) |
                    bytes32(uint256(uint8(assetType)))
            );
    }

    receive() external payable {}
}

contract StateZeroTest is StateZero {
    
    function testJoin() public {
        console2.log("join pulls fCash from user");

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(njoin), user, address(njoin), fCashId, 1e8);
        fCashTokens = fCash.balanceOf(user, fCashId);
        vm.prank(me);
        njoin.join(user, 1e8);

        assertTrue(njoin.storedBalance() ==  1e8);
        assertTrue(fCash.balanceOf(user, fCashId) ==  fCashTokens - 1e8);
    }
}

// Njoin receives fCash tokens from user
abstract contract StateJoined is StateZero {
    function setUp() public override virtual {
        super.setUp();
        vm.prank(me);
        njoin.join(user, 2e8);

    }
}

// Njoin has 2e8 fCash | storedBalance = 2e8
contract StateJoinedTest is StateJoined {

    function testAcceptSurplus() public {
        console2.log("accepts surplus as a transfer");
        
        fCashTokens = fCash.balanceOf(user, fCashId);
        //surplus 
        vm.prank(user);
        fCash.safeTransferFrom(user, address(njoin), fCashId, 1e8, "");
        // no TransferSingle event emitted
        vm.prank(me);
        njoin.join(user, 1e8);
        
        assertTrue(njoin.storedBalance() ==  3e8);
        assertTrue(fCash.balanceOf(user, fCashId) ==  fCashTokens - 1e8);

    }

    function testSurplusRegistered() public {
        console2.log("combines surplus and fCashs pulled from the user");
        fCashTokens = fCash.balanceOf(user, fCashId);
        // surplus of 1e8
        vm.prank(user);
        fCash.safeTransferFrom(user, address(njoin), fCashId, 1e8, "");

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(njoin), user, address(njoin), fCashId, 1e8);
        
        // 1e8 transferred from user | 1e8 taken from surplus
        vm.prank(me);
        njoin.join(user, 2e8);

        assertTrue(njoin.storedBalance() ==  4e8);
        assertTrue(fCash.balanceOf(user, fCashId) ==  fCashTokens - 2e8);
    }
}

abstract contract StatePositiveStoredBalance is StateJoined {
    function setUp() public override virtual {
        super.setUp(); 
    }
}

// Njoin holds 2e8 of fCash
contract StatePositiveStoredBalanceTest is StatePositiveStoredBalance {
    function testExit() public {
        console2.log("pushes fCash to user");
        fCashTokens = fCash.balanceOf(user, fCashId);
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(njoin), address(njoin), user, fCashId, 1e8);
        vm.prank(me);
        njoin.exit(user, 1e8);

        assertTrue(njoin.storedBalance() ==  1e8);
        assertTrue(fCash.balanceOf(user, fCashId) ==  fCashTokens + 1e8);

    }
}

// Njoin holds 2e8 of fCash
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
        vm.prank(me);
        njoin.join(user, 1e8);
    }

    function testRedeem() public {
        console2.log("First exit call should call redeem()");
        (address currency,uint16 currencyId ) = whichCurrency(fCashId);
        
        assertTrue(njoin.accrual() == 0);
        vm.expectEmit(true, true, true, false);
        emit Redeemed(0, 10e8, 1e8);
        uint beforeUserBalance = IERC20(currency).balanceOf(user);
        uint beforeJoinBalance = IERC20(currency).balanceOf(address(underlyingJoin));
        vm.prank(me);
        njoin.exit(user, 1e8);
        
        assertGt(njoin.accrual(), 0);
        assertTrue(njoin.storedBalance() == 0);
        assertTrue(IERC20(currency).balanceOf(address(njoin)) == 0); 
        uint afterUserBalance = IERC20(currency).balanceOf(user);
        uint afterJoinBalance = IERC20(currency).balanceOf(address(underlyingJoin));
        
        if(currencyId == 3){
            assertApproxEqAbs(afterUserBalance - beforeUserBalance, 1e6, 1e5);
            assertApproxEqAbs(afterJoinBalance - beforeJoinBalance, 1e6, 1e5);
        }else{
            assertApproxEqAbs(afterUserBalance - beforeUserBalance, 1e18, 1e17);
            assertApproxEqAbs(afterJoinBalance - beforeJoinBalance, 1e18, 1e17);
        }
    }
}

abstract contract StateRedeemed is StateMatured {

     function setUp() public override virtual {
        super.setUp();

        // state transition: accrual > 0         
        vm.prank(me);
        njoin.exit(user, 1e8);
        assertGt(njoin.accrual(),0);
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
        (address currency, uint16 currencyId) = whichCurrency(fCashId);
        uint beforeUserBalance = IERC20(currency).balanceOf(user);
        uint beforeJoinBalance = IERC20(currency).balanceOf(address(underlyingJoin));
        vm.prank(me);
        njoin.exit(user, 1e8);

        assertTrue(njoin.storedBalance() == 0); 
        assertTrue(IERC20(currency).balanceOf(address(njoin)) == 0); 
        uint afterUserBalance = IERC20(currency).balanceOf(user);
        uint afterJoinBalance = IERC20(currency).balanceOf(address(underlyingJoin));
        if(currencyId == 3){
            assertApproxEqAbs(afterUserBalance - beforeUserBalance, 1e6, 1e5);
            assertApproxEqAbs(beforeJoinBalance - afterJoinBalance, 1e6, 1e5);
        }else{
            assertApproxEqAbs(afterUserBalance - beforeUserBalance, 1e18, 1e17);
            assertApproxEqAbs(beforeJoinBalance - afterJoinBalance, 1e18, 1e17);
        }
        
    }
}
