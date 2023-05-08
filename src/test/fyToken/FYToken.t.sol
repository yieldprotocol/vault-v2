// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import { IERC20 } from "@yield-protocol/utils-v2/src/token/IERC20.sol";
import { Cauldron } from "../../Cauldron.sol";
import { FYToken } from "../../FYToken.sol";
import { Join } from "../../Join.sol";
import { IJoin } from "../../interfaces/IJoin.sol";
import { ILadle } from "../../interfaces/ILadle.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { CTokenChiMock } from "../../mocks/oracles/compound/CTokenChiMock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { TestExtensions } from "../utils/TestExtensions.sol";

abstract contract ZeroState is Test, TestConstants, TestExtensions {
    using Cast for *;

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

    function setUpMock() public {
        timelock = address(1);
        cauldron = Cauldron(address(2));
        ladle = ILadle(address(3));

        oracle = IOracle(address(new CTokenChiMock()));
        CTokenChiMock(address(oracle)).set(220434062002504964823286680);

        token = IERC20(address(new ERC20Mock("", "")));
        bytes6 mockIlkId = 0x000000000001;
        join = new Join(address(token));

        fyToken = new FYToken(
            mockIlkId,
            oracle,
            join,
            1719583200,
            "",
            ""
        );

        fyToken.grantRole(fyToken.point.selector, address(timelock));
        fyToken.grantRole(fyToken.mature.selector, address(timelock));
        fyToken.grantRole(fyToken.mint.selector, address(ladle));
        join.grantRole(join.join.selector, address(fyToken));
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
    } 

    function setUp() public virtual {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);
        string memory network = vm.envOr(NETWORK, LOCALHOST);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);

        user = address(4);
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());

        vm.label(address(cauldron), "cauldron");
        vm.label(address(ladle), "ladle");
        vm.label(user, "user");
        vm.label(address(token), "token");
        vm.label(address(fyToken), "fyToken");
        vm.label(address(oracle), "oracle");
        vm.label(address(join), "join");

        // user has 100 tokens and fyTokens
        cash(token, user, 100 * unit);
        cash(fyToken, user, 100 * unit);
        // fyToken contract has 100 tokens and fyTokens
        cash(token, address(fyToken), 100 * unit);
        // ladle has 100 tokens
        cash(token, address(ladle), 100 * unit);

        // provision Join if using mocks
        if (vm.envOr(MOCK, true)) {
            cash(token, address(this), unit * 200);
            token.approve(address(join), unit * 200);
            join.join(address(this), unit * 200);
        }
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

    function testMintWithUnderlying() public {
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

    function testConvertToPrincipal() public {
        console.log("can convert amount of underlying to principal");
        assertEq(fyToken.convertToPrincipal(unit), unit);
    }

    function testConvertToUnderlying() public {
        console.log("can convert amount of principal to underlying");
        assertEq(fyToken.convertToUnderlying(unit), unit);
    }

    function testPreviewRedeem() public {
        console.log("can preview the amount of underlying redeemed");
        assertEq(fyToken.previewRedeem(unit), unit);
    }

    function testPreviewWithdraw() public {
        console.log("can preview the amount of principal withdrawn");
        assertEq(fyToken.previewWithdraw(unit), unit);
    }
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

    function testMatureRevertsOnZeroChi() public {
        console.log("can't mature if chi is zero");

        CTokenChiMock chiOracle = new CTokenChiMock(); // Use a new oracle that we can force to be zero
        chiOracle.set(0);

        vm.startPrank(timelock);
        fyToken.point("oracle", address(chiOracle));
        vm.expectRevert("Chi oracle malfunction");
        fyToken.mature();
        vm.stopPrank();
    }

    // uses underlyingId so only
    function testMatureRecordsChiValue() public {
        console.log("records chi value when matured");
        vm.startPrank(timelock);
        uint256 chiAtMaturity;
        (chiAtMaturity, ) = oracle.get(fyToken.underlyingId(), CHI, 0);        
        vm.expectEmit(false, false, false, true);
        emit SeriesMatured(chiAtMaturity);
        fyToken.mature();
        vm.stopPrank();
        assert(fyToken.chiAtMaturity() != type(uint256).max && fyToken.chiAtMaturity() > 0);
    }

    function testMaturesFirstRedemptionAfterMaturity() public {
        console.log("matures on first redemption after maturity if needed");
        track("userTokenBalance", token.balanceOf(user));
        track("userFYTokenBalance", fyToken.balanceOf(user));

        uint256 chiAtMaturity;
        (chiAtMaturity, ) = oracle.get(fyToken.underlyingId(), CHI, 0);        
        vm.expectEmit(false, false, false, true);
        emit SeriesMatured(chiAtMaturity);
        
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user, 
            user, 
            unit, 
            unit
        );

        vm.prank(user);
        fyToken.redeem(unit, user, user);

        assertEq(fyToken.chiAtMaturity(), chiAtMaturity);
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
    function testCannotChangeOracle() public {
        console.log("can't change the CHI oracle once matured");
        vm.expectRevert("Already matured");
        vm.prank(timelock);
        fyToken.point("oracle", address(this));
    }

    function testChiAccrualNotBelowOne() public {
        console.log("cannot have chi accrual below 1");
        assertGt(fyToken.accrual(), 0);
    }

    function testConvertToUnderlyingWithAccrual() public {
        console.log("can convert the amount of underlying plus the accrual to principal");
        assertEq(fyToken.convertToUnderlying(unit), unit * 110 / 100);
        assertEq(fyToken.convertToUnderlying(unit * 5), unit * 5 * 110 / 100);
    }

    function testConvertToPrincipalWithAccrual() public {
        console.log("can convert the amount of underlying plus the accrual to principal");
        assertEq(fyToken.convertToPrincipal(unit * 110 / 100), unit);
        assertEq(fyToken.convertToPrincipal(unit * 5 * 110 / 100), unit * 5);
    }

    function testMaxRedeem() public {
        console.log("can get the max amount of principal redeemable");
        assertEq(fyToken.maxRedeem(user), unit * 100);
    }

    function testMaxWithdraw() public {
        console.log("can get the max amount of underlying withdrawable");
        assertEq(fyToken.maxRedeem(user), unit * 100);
    }

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

    function testRedeemOnTransfer() public {
        console.log("redeems when transfering to the fyToken contract");
        track("userTokenBalance", token.balanceOf(user));
        track("userFYTokenBalance", fyToken.balanceOf(user));

        vm.startPrank(user);
        fyToken.transfer(address(fyToken), unit);
        assertEq(fyToken.balanceOf(address(this)), 0);
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user,
            user, 
            unit, 
            unit * 110 / 100
        );
        fyToken.redeem(user, 0);
        vm.stopPrank();

        assertTrackPlusEq("userTokenBalance", unit * 110 / 100, token.balanceOf(user));
        assertTrackMinusEq("userFYTokenBalance", unit, fyToken.balanceOf(user));
    }

    function testRedeemOnFractionalTransfer() public {
        console.log("redeems by transfer and approve combination");
        track("userTokenBalance", token.balanceOf(user));
        track("userFYTokenBalance", fyToken.balanceOf(user));

        // will redeem half a unit from the contract and half from the user
        vm.startPrank(user);
        fyToken.transfer(address(fyToken), unit / 2);
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

    function testRedeemERC5095() public {
        console.log("redeems with ERC5095 redeem");
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
        fyToken.redeem(unit, user, user);

        assertTrackPlusEq("userTokenBalance", unit * 110 / 100, token.balanceOf(user));
        assertTrackMinusEq("userFYTokenBalance", unit, fyToken.balanceOf(user));
    }

    function testRedeemWithZeroAmount() public {
        console.log("Redeems the contract's fyToken balance when amount is 0");
        cash(fyToken, address(fyToken), unit * 100);

        track("userTokenBalance", token.balanceOf(user));
        track("fyTokenfyTokenBalance", fyToken.balanceOf(address(fyToken)));

        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user, 
            user, 
            fyToken.balanceOf(address(fyToken)), 
            fyToken.balanceOf(address(fyToken)) * 110 / 100
        );
        vm.prank(user);
        fyToken.redeem(0, user, user);

        // user's balance will increase by 100 tokens with accrual
        // fyToken's balance will decrease by its balance of 100 fyTokens
        assertTrackPlusEq("userTokenBalance", unit * 100 * 110 / 100, token.balanceOf(user));
        assertTrackMinusEq("fyTokenfyTokenBalance", unit * 100, fyToken.balanceOf(address(fyToken)));
    }

    function testRedeemApproval() public {
        console.log("can redeem only the approved amount from holder");
        track("userFYTokenBalance", fyToken.balanceOf(user));
        track("thisTokenBalance", token.balanceOf(address(this)));

        vm.prank(user);
        fyToken.approve(address(this), unit * 5);

        vm.expectRevert("ERC20: Insufficient approval");
        fyToken.redeem(
            unit * 10, 
            address(this), 
            user
        );

        fyToken.redeem(
            unit * 4,
            address(this),
            user
        );

        assertTrackMinusEq("userFYTokenBalance", unit * 4, fyToken.balanceOf(user));
        assertTrackPlusEq("thisTokenBalance", unit * 4 * 110 / 100, token.balanceOf(address(this)));
    }

    function testWithdrawERC5095() public {
        console.log("withdrwas with ERC5095 withdraw");
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
        fyToken.withdraw(unit * 110 / 100, user, user);

        assertTrackPlusEq("userTokenBalance", unit * 110 / 100, token.balanceOf(user));
        assertTrackMinusEq("userFYTokenBalance", unit, fyToken.balanceOf(user));
    }

    function testWithdrawWithZeroAmount() public {
        console.log("Withdraws the contract's fyToken balance when amount is 0");
        cash(fyToken, address(fyToken), 100 * unit);
        
        track("userTokenBalance", token.balanceOf(user));
        track("fyTokenfyTokenBalance", fyToken.balanceOf(address(fyToken)));
        
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            user, 
            user, 
            fyToken.balanceOf(address(fyToken)),
            fyToken.balanceOf(address(fyToken)) * 110 / 100
        );
        vm.prank(user);
        fyToken.withdraw(0, user, user);

        // user's balance will increase by 100 tokens with accrual
        // fyToken's balance will decrease by its balance of 100 fyTokens
        assertTrackPlusEq("userTokenBalance", unit * 100 * 110 / 100, token.balanceOf(user));
        assertTrackMinusEq("fyTokenfyTokenBalance", unit * 100, fyToken.balanceOf(address(fyToken)));
    }

    function testWithdrawApproval() public {
        console.log("can redeem only the approved amount from holder");
        track("userFYTokenBalance", fyToken.balanceOf(user));
        track("thisTokenBalance", token.balanceOf(address(this)));

        vm.prank(user);
        fyToken.approve(address(this), unit * 5);

        vm.expectRevert("ERC20: Insufficient approval");
        fyToken.withdraw(
            unit * 10 * 110 / 100, 
            address(this), 
            user
        );

        fyToken.withdraw(
            unit * 4 * 110 / 100,
            address(this),
            user
        );

        assertTrackMinusEq("userFYTokenBalance", unit * 4, fyToken.balanceOf(user));
        assertTrackPlusEq("thisTokenBalance", unit * 4 * 110 / 100, token.balanceOf(address(this)));
    }
}