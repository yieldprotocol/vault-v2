// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import { IERC20 } from "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import { Cauldron } from "../../Cauldron.sol";
import { FYToken } from "../../FYToken.sol";
import { Join } from "../../Join.sol";
import { ILadle } from "../../interfaces/ILadle.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { CTokenChiMock } from "../../mocks/oracles/compound/CTokenChiMock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { FlashBorrower } from "../../mocks/FlashBorrower.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { TestExtensions } from "../utils/TestExtensions.sol";

abstract contract ZeroState is Test, TestConstants, TestExtensions {
    using CastU256I128 for uint256;

    event Point(bytes32 indexed param, address value);
    event SeriesMatured(uint256 chiAtMaturity);
    event Redeemed(address indexed from, address indexed to, uint256 amount, uint256 redeemed);
    event Transfer(address indexed src, address indexed dst, uint wad);

    address public timelock;
    Cauldron public cauldron;
    ILadle public ladle;
    IERC20 public token; 
    FYToken public fyToken;
    Join public join;
    FlashBorrower public borrower;
    IOracle public oracle; 
    CTokenChiMock public mockOracle;
    uint128 public unit;
    address user;

    function setUpMock() public {
        timelock = address(1);
        cauldron = Cauldron(address(2));
        ladle = ILadle(address(3));

        mockOracle = new CTokenChiMock();
        mockOracle.set(220434062002504964823286680); 

        token = IERC20(address(new ERC20Mock("", "")));
        bytes6 mockIlkId = 0x000000000001;
        join = new Join(address(token));

        fyToken = new FYToken(
            mockIlkId,
            IOracle(address(mockOracle)),
            join,
            1680427572,
            "",
            ""
        );

        fyToken.grantRole(fyToken.setFlashFeeFactor.selector, address(timelock));
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
        string memory rpc = vm.envOr(RPC, HARNESS);
        vm.createSelectFork(rpc);
        string memory network = vm.envOr(NETWORK, LOCALHOST);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness(network);

        borrower = new FlashBorrower(fyToken);

        user = address(4);
        unit = uint128(10 ** ERC20Mock(address(token)).decimals());

        vm.label(address(cauldron), "cauldron");
        vm.label(address(ladle), "ladle");
        vm.label(user, "user");
        vm.label(address(token), "token");
        vm.label(address(fyToken), "fyToken");
        vm.label(address(oracle), "oracle");
        vm.label(address(join), "join");
    }
}

abstract contract WithZeroFee is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        vm.prank(timelock);
        fyToken.setFlashFeeFactor(0);
    }
}

abstract contract WithNonZeroFee is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        vm.prank(timelock);
        fyToken.setFlashFeeFactor(unit * 5 / 100);
    }
}

abstract contract AfterMaturity is WithZeroFee {
    function setUp() public override {
        super.setUp();
        vm.warp(fyToken.maturity());
    }
}

contract FYTokenFlashTest is ZeroState {
    function testFlashLoanDisabledByDefault() public {
        console.log("cannot do flash loan by default");
        vm.expectRevert("Cast overflow");                   // fee factor hasn't been set
        vm.prank(user);
        fyToken.flashLoan(borrower, address(fyToken), 1, bytes(hex"00"));
    }

}

contract WithZeroFeeTest is WithZeroFee {
    function testFlashBorrow() public {
        console.log("can do a simple flash borrow");
        vm.prank(user);
        borrower.flashBorrow(address(fyToken), unit, FlashBorrower.Action.NORMAL);

        assertEq(fyToken.balanceOf(user), 0);
        assertEq(borrower.flashBalance(), unit);
        assertEq(borrower.flashToken(), address(fyToken));
        assertEq(borrower.flashAmount(), unit);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testRepayWithTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(fyToken), address(0), unit);
        vm.prank(user);
        borrower.flashBorrow(address(fyToken), unit, FlashBorrower.Action.TRANSFER);

        assertEq(fyToken.balanceOf(user), 0);
        assertEq(borrower.flashBalance(), unit);
        assertEq(borrower.flashToken(), address(fyToken));
        assertEq(borrower.flashAmount(), unit);
        assertEq(borrower.flashFee(), 0);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testApproveNonInitiator() public {
        vm.expectRevert("ERC20: Insufficient approval");
        vm.prank(user);
        fyToken.flashLoan(
            borrower, 
            address(fyToken), 
            unit, 
            bytes(abi.encode(0))
        );
    }

    function testEnoughFundsForLoanRepay() public {
        vm.expectRevert("ERC20: Insufficient balance");
        vm.prank(user);
        borrower.flashBorrow(address(fyToken), unit, FlashBorrower.Action.STEAL);
    }

    function testNestedFlashLoans() public {
        borrower.flashBorrow(address(fyToken), unit, FlashBorrower.Action.REENTER);
        vm.prank(user);
        assertEq(borrower.flashBalance(), unit * 3);
    }
}

contract WithNonZeroFeeTest is WithNonZeroFee {
    function testFlashLoan() public {
        if (!vm.envOr(MOCK, true))vm.prank(timelock);
        fyToken.grantRole(fyToken.mint.selector, address(this));
        fyToken.mint(address(borrower), unit * 5 / 100);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(borrower), address(0), unit + (unit * 5 / 100));
        borrower.flashBorrow(address(fyToken), unit, FlashBorrower.Action.NORMAL);
    }}

contract AfterMaturityTest is AfterMaturity {
    function testNoFlashBorrowAfterMaturity() public {
        console.log("cannot flash borrow after maturity");
        vm.expectRevert("Only before maturity");
        vm.prank(user);
        borrower.flashBorrow(address(fyToken), unit, FlashBorrower.Action.NORMAL);
    }
}