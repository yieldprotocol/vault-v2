// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import { IERC20 } from "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { Cauldron } from "../../Cauldron.sol";
import { FYToken } from "../../FYToken.sol";
import { Join } from "../../Join.sol";
import { IJoin } from "../../interfaces/IJoin.sol";
import { ILadle } from "../../interfaces/ILadle.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import "../../oracles/uniswap/uniswapv0.8/FullMath.sol";
import { CTokenChiMock } from "../../mocks/oracles/compound/CTokenChiMock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { TestExtensions } from "../TestExtensions.sol";

abstract contract ZeroState is Test, TestConstants, TestExtensions {
    using CastU256I128 for uint256;

    event Point(bytes32 indexed param, address value);
    event SeriesMatured(uint256 chiAtMaturity);
    event Redeemed(address indexed from, address indexed to, uint256 amount, uint256 redeemed);

    FYToken public fyToken;
    Join public join;
    address public timelock;
    Cauldron public cauldron;
    IERC20 public token;
    uint128 public unit;
    address user;

    ILadle public ladle;
    IOracle public oracle;
    CTokenChiMock public mockOracle;

    modifier onlyHarness() {
        if (vm.envOr(MOCK, true)) return; // Absence of MOCK makes it default to true
        _;
    }

    modifier onlyMock() {
        if (!vm.envOr(MOCK, true)) return;
        _;
    }

    function setUpMock() public {
        timelock = address(1);
        cauldron = Cauldron(address(2));
        ladle = ILadle(address(3));

        mockOracle = new CTokenChiMock();
        mockOracle.set(220434062002504964823286680); 

        token = IERC20(address(new ERC20Mock("", "")));
        bytes6 mockIlkId = 0x000000000001;
        join = new Join(address(token)); // Maybe you need to `join` some token into this Join, so that it can serve redemptions. Give yourself permissions if needed.

        fyToken = new FYToken(
            mockIlkId,
            IOracle(address(mockOracle)),
            join,
            1680427572,
            "",
            ""
        );

        fyToken.grantRole(fyToken.point.selector, address(timelock));
        fyToken.grantRole(fyToken.mature.selector, address(timelock));
        fyToken.grantRole(fyToken.mint.selector, address(ladle));
        join.grantRole(join.exit.selector, address(fyToken));

        join.grantRole(join.join.selector, address(this));
    }

    function setUpHarness(string memory network) public {
        timelock = addresses[network][TIMELOCK];
        cauldron = Cauldron(addresses[network][CAULDRON]);
        ladle = ILadle(addresses[network][LADLE]);

        fyToken = FYToken(vm.envAddress("FYTOKEN"));
        join = Join(address(fyToken.join()));
        token = IERC20(fyToken.underlying());
        oracle = fyToken.oracle();

        vm.prank(address(timelock));
        join.grantRole(join.join.selector, address(this));
    } 

    function setUp() public virtual {
        string memory network = vm.envOr(NETWORK, LOCALHOST);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);

        user = address(1);
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());

        vm.label(address(cauldron), "cauldron");
        vm.label(address(ladle), "ladle");
        vm.label(user, "user");
        vm.label(address(token), "token");
        vm.label(address(oracle), "oracle");
        vm.label(address(join), "join");

        cash(token, user, 100 * unit);
        cash(token, address(ladle), 100 * unit);
        cash(fyToken, user, 100 * unit);

        // provision join
        cash(token, address(this), unit * 100);
        token.approve(address(join), unit * 100);
        join.join(address(this), unit * 100);
    }
}

contract FYTokenTest is ZeroState {
    function testChangeOracle() public {
        console.log("can change the CHI oracle");
        vm.expectEmit(true, false, false, true);
        emit Point("oracle", address(this));
        vm.prank(timelock);
        fyToken.point("oracle", address(this));
        assertEq(address(fyToken.oracle()), address(this));
    }

    function testChangeJoin() public {
        console.log("can change Join");
        vm.expectEmit(true, false, false, true);
        emit Point("join", address(this));
        vm.prank(timelock);
        fyToken.point("join", address(this));
        assertEq(address(fyToken.join()), address(this));
    }

    // tries to transfer from join so onlyHarness
    // You can put funds in the mock join, see above 
    function testMintWithUnderlying() public onlyHarness {
        console.log("can mint with underlying");
        track("userTokenBalance", fyToken.balanceOf(user));
        
        vm.prank(address(ladle));
        token.approve(address(join), unit);
        vm.prank(address(ladle));
        fyToken.mintWithUnderlying(user, unit);

        assertTrackPlusEq("userTokenBalance", unit, fyToken.balanceOf(user));
    }

    function testCantMatureBeforeMaturity() public {
        console.log("can't mature before maturity");
        vm.prank(timelock);
        vm.expectRevert("Only after maturity");
        fyToken.mature();
    }

    function testCantRedeemBeforeMaturity() public {
        console.log("can't redeem before maturity");
        vm.expectRevert("Only after maturity");
        vm.prank(user);
        fyToken.redeem(user, unit);
    }

    // not on live contracts
    // Have I got a fork for you: https://rpc.tenderly.co/fork/78da602e-78a8-4705-b73c-3c62991231aa
    // Addresses here: https://github.com/yieldprotocol/environments-v2/tree/feat/new-identifiers/addresses/tenderly_mainnet
    // Example here: https://github.com/yieldprotocol/strategy-v2/blob/fix/audit-fixes/test/harness/StrategyHarness.t.sol
    // function testConvertToPrincipal() public {
    //     console.log("can convert amount of underlying to principal");
    //     assertEq(fyToken.convertToPrincipal(1000), 1000);
    // }

    // function testConvertToUnderlying() public {
    //     console.log("can convert amount of principal to underlying");
    //     assertEq(fyToken.convertToUnderlying(1000), 1000);
    // }

    // function testPreviewRedeem() public {
    //     console.log("can preview the amount of underlying redeemed");
    //     assertEq(fyToken.previewRedeem(unit), unit);
    // }

    // function testPreviewWithdraw() public {
    //     console.log("can preview the amount of principal withdrawn");
    //     assertEq(fyToken.previewWithdraw(unit), unit);
    // }
}

abstract contract AfterMaturity is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        vm.warp(fyToken.maturity());
    }
}

contract AfterMaturityTest is AfterMaturity {
    function testCantMintAfterMaturity() public {
        console.log("can't mint after maturity");
        vm.expectRevert("Only before maturity");
        vm.prank(address(ladle));
        fyToken.mint(user, unit);
    }

    function testMatureOnlyOnce() public {
        console.log("can only mature once");
        vm.prank(timelock);
        fyToken.mature();
        vm.expectRevert("Already matured");
        fyToken.mature();
    }

    // live contracts do not have the require
    // function testMatureRevertsOnZeroChi() public {
    //     console.log("can't mature if chi is zero");

    //     CTokenChiMock chiOracle = new CTokenChiMock(); // Use a new oracle that we can force to be zero
    //     chiOracle.set(0);

    //     vm.startPrank(timelock);
    //     fyToken.point("oracle", address(chiOracle));
    //     vm.expectRevert("Chi oracle malfunction");
    //     fyToken.mature();
    //     vm.stopPrank();
    // }

    function testMatureRecordsChiValue() public {
        console.log("records chi value when matured");
        vm.prank(timelock);
        // should we still test this emit?
        // vm.expectEmit(false, false, false, true);
        // emit SeriesMatured(220434062002504964823286680);
        fyToken.mature();
        // Please test the state change and event
    }

    // made onlyHarness since no way to associate mockIlk with mockERC20?
    function testMaturesFirstRedemptionAfterMaturity() public onlyHarness {
        console.log("matures on first redemption after maturity if needed");
        track("userTokenBalance", token.balanceOf(user));
        track("userFYTokenBalance", fyToken.balanceOf(user));

        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user, 
            user, 
            unit, 
            unit
        );
        vm.prank(user);
        fyToken.redeem(user, unit);

        assertTrackPlusEq("userTokenBalance", unit, token.balanceOf(user));
        assertTrackMinusEq("userFYTokenBalance", unit, fyToken.balanceOf(user));
    }
}

abstract contract OnceMatured is AfterMaturity {
    CTokenChiMock public chiOracle;
    uint256 accrual = unit * 110 / 100;                                       // 10%
    address fyTokenHolder = address(1);

    function setUp() public override {
        super.setUp();
        chiOracle = new CTokenChiMock();
        vm.startPrank(timelock);
        chiOracle.set(unit);                                                  // set the redeem to 1:1 will add accrual below
        fyToken.point("oracle", address(chiOracle));                          // Uses new oracle to update to new chi value
        fyToken.mature();
        vm.stopPrank();
        chiOracle.set(fyToken.chiAtMaturity() * 110 / 100);                   // Will set chi returned to be unit + 10%
    }
}

contract OnceMaturedTest is OnceMatured {
    // not on live contracts
    // function testCannotChangeOracle() public {
    //     console.log("can't change the CHI oracle once matured");
    //     vm.expectRevert("Already matured");
    //     vm.prank(timelock);
    //     fyToken.point("oracle", address(this));
    // }

    function testChiAccrualNotBelowOne() public {
        console.log("cannot have chi accrual below 1");
        assertGt(fyToken.accrual(), 0);
    }

    // not on live contracts
    // function testConvertToUnderlyingWithAccrual() public {
    //     console.log("can convert the amount of underlying plus the accrual to principal");
    //     assertEq(fyToken.convertToUnderlying(1000), 1100);
    //     assertEq(fyToken.convertToUnderlying(5000), 5500);
    // }

    // function testConvertToPrincipalWithAccrual() public {
    //     console.log("can convert the amount of underlying plus the accrual to principal");
    //     assertEq(fyToken.convertToPrincipal(1100), 1000);
    //     assertEq(fyToken.convertToPrincipal(5500), 5000);
    // }

    // function testMaxRedeem() public {
    //     console.log("can get the max amount of principal redeemable");
    //     deal(address(fyToken), address(this), WAD * 2);
    //     assertEq(fyToken.maxRedeem(address(this)), WAD * 2);
    // }

    // function testMaxWithdraw() public {
    //     console.log("can get the max amount of underlying withdrawable");
    //     deal(address(fyToken), address(this), WAD * 2);
    //     assertEq(fyToken.maxRedeem(address(this)), WAD * 2);
    // }

    // needs to transfer from join so onlyHarness
    function testRedeemWithAccrual() public {
        console.log("redeems according to chi accrual");
        track("userTokenBalance", token.balanceOf(user));
        track("userFYTokenBalance", fyToken.balanceOf(user));
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user, 
            user, 
            unit, 
            unit * 110 / 100
        );
        vm.prank(user);
        fyToken.redeem(user, unit);
        assertTrackPlusEq("userTokenBalance", unit * 110 / 100, token.balanceOf(user));
        assertTrackMinusEq("userFYTokenBalance", unit, fyToken.balanceOf(user));
    }

    // needs to transfer from join so onlyHarness
    function testRedeemOnTransfer() public onlyHarness {
        console.log("redeems when transfering to the fyToken contract");
        track("userTokenBalance", token.balanceOf(user));
        track("userFYTokenBalance", fyToken.balanceOf(user));
        vm.startPrank(user);
        fyToken.transfer(address(fyToken), WAD);
        assertEq(fyToken.balanceOf(address(this)), 0);
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user,
            user, 
            unit, 
            unit * 110 / 100
        );
        fyToken.redeem(user, unit);
        vm.stopPrank();
        assertTrackPlusEq("userTokenBalance", unit * 110 / 100, token.balanceOf(user));
        assertTrackMinusEq("userFYTokenBalance", unit, fyToken.balanceOf(user));
    }

    // only possible with 5095 redeem?
    // function testRedeemByTransferAndApprove() public {
    //     console.log("redeems by transfer and approve combination");
    //     uint256 ownerBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(this));
    //     uint256 joinBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(join));
    //     fyToken.transfer(address(fyToken), WAD / 2);
    //     assertEq(fyToken.balanceOf(address(this)), WAD / 2);
    //     vm.expectEmit(true, true, false, true);
    //     emit Redeemed(
    //         address(this), 
    //         address(this), 
    //         WAD,
    //         FullMath.mulDiv(WAD, accrual, WAD)
    //     );
    //     fyToken.redeem(WAD, address(this), address(this));
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(this)), 
    //         ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
    //     );
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(join)), 
    //         joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
    //     );        
    // }

    // not available for live contracts
    // function testRedeemERC5095() public {
    //     console.log("redeems with ERC5095 redeem");
    //     uint256 ownerBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(this));
    //     uint256 joinBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(join));
    //     vm.expectEmit(true, true, false, true);
    //     emit Redeemed(
    //         address(this), 
    //         address(this), 
    //         WAD, 
    //         FullMath.mulDiv(WAD, accrual, WAD)
    //     );
    //     fyToken.redeem(WAD, address(this), address(this));
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(this)), 
    //         ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
    //     );
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(join)), 
    //         joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
    //     );        
    // }

    function testRedeemWithZeroAmount() public onlyHarness {
        console.log("Redeems the contract's balance when amount is 0");
        track("userTokenBalance", token.balanceOf(user));
        track("fyTokenTokenBalance", token.balanceOf(address(fyToken)));
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user, 
            user, 
            fyToken.balanceOf(address(fyToken)), 
            fyToken.balanceOf(address(fyToken)) * 110 / 100
        );
        vm.prank(user);
        // fyToken.redeem(0, user, user);
        fyToken.redeem(user, 0);
        assertTrackPlusEq("userTokenBalance", token.balanceOf(address(fyToken)), token.balanceOf(user));
        assertTrackMinusEq("fyTokenTokenBalance", token.balanceOf(address(fyToken)), token.balanceOf(address(fyToken)));
    }

    // not available for live contracts
    // function testRedeemApproval() public {
    //     console.log("can redeem only the approved amount from holder");
    //     uint256 ownerBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(this));
    //     uint256 joinBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(join));
    //     deal(address(fyToken), fyTokenHolder, WAD * 5);
    //     vm.prank(fyTokenHolder);
    //     fyToken.approve(address(this), WAD * 5);

    //     vm.expectRevert("ERC20: Insufficient approval");
    //     fyToken.redeem(
    //         WAD * 10, 
    //         address(this), 
    //         fyTokenHolder
    //     );

    //     fyToken.redeem(
    //         WAD * 4,
    //         address(this),
    //         fyTokenHolder
    //     );
    //     assertEq(fyToken.balanceOf(fyTokenHolder), WAD);
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(this)), 
    //         ownerBalanceBefore + FullMath.mulDiv(WAD * 4, accrual, WAD)
    //     );
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(join)),
    //         joinBalanceBefore - FullMath.mulDiv(WAD * 4, accrual, WAD)
    //     );
    // }

    // not available for live contracts
    // function testWithdrawERC5095() public {
    //     console.log("withdrwas with ERC5095 withdraw");
    //     uint256 ownerBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(this));
    //     uint256 joinBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(join));
    //     vm.expectEmit(true, true, false, true);
    //     emit Redeemed(
    //         address(this), 
    //         address(this), 
    //         WAD, 
    //         FullMath.mulDiv(WAD, accrual, WAD)
    //     );
    //     fyToken.withdraw(FullMath.mulDiv(WAD, accrual, WAD), address(this), address(this));
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(this)), 
    //         ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
    //     );
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(join)), 
    //         joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
    //     );
    // }

    // withdraw function not available on live contracts
    // function testWithdrawWithZeroAmount() public {
    //     console.log("Withdraws the contract's balance when amount is 0");
    //     uint256 ownerBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(this));
    //     uint256 joinBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(join));
    //     deal(address(fyToken), address(fyToken), WAD * 10);

    //     vm.expectEmit(true, true, false, true);
    //     emit Redeemed(
    //         address(this), 
    //         address(this), 
    //         WAD * 10, 
    //         FullMath.mulDiv(WAD * 10, accrual, WAD)
    //     );
    //     fyToken.withdraw(0, address(this), address(this));
    //     assertEq(
    //         fyToken.balanceOf(address(fyToken)), 
    //         0
    //     );
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(this)), 
    //         ownerBalanceBefore + FullMath.mulDiv(WAD * 10, accrual, WAD)
    //     );
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(join)),
    //         joinBalanceBefore - FullMath.mulDiv(WAD * 10, accrual, WAD)
    //     );
    // }

    // function testWithdrawApproval() public {
    //     console.log("can withdraw only the approved amount from holder");
    //     uint256 ownerBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(this));
    //     uint256 joinBalanceBefore = IERC20(fyToken.underlying()).balanceOf(address(join));
    //     deal(address(fyToken), fyTokenHolder, WAD * 5);
    //     vm.prank(fyTokenHolder);
    //     fyToken.approve(address(this), WAD * 5);

    //     uint256 amountToWithdraw = fyToken.convertToUnderlying(WAD * 10);     // so revert works properly
    //     vm.expectRevert("ERC20: Insufficient approval");
    //     fyToken.withdraw(
    //         amountToWithdraw,
    //         address(this),
    //         fyTokenHolder
    //     );

    //     fyToken.withdraw(
    //         fyToken.convertToUnderlying(WAD * 4),
    //         address(this),
    //         fyTokenHolder
    //     );
    //     assertEq(fyToken.balanceOf(fyTokenHolder), WAD);
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(this)),
    //         ownerBalanceBefore + FullMath.mulDiv(WAD * 4, accrual, WAD)
    //     );
    //     assertEq(
    //         IERC20(fyToken.underlying()).balanceOf(address(join)),
    //         joinBalanceBefore - FullMath.mulDiv(WAD * 4, accrual, WAD)
    //     );
    // }
}