// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "../../Cauldron.sol";
import "../../FYToken.sol";
import "../../Join.sol";
import "../../interfaces/ILadle.sol";
import "../../oracles/uniswap/uniswapv0.8/FullMath.sol";
import "../../mocks/oracles/compound/CTokenChiMock.sol";
import "../../mocks/FlashBorrower.sol";
import "../utils/TestConstants.sol";


abstract contract ZeroState is Test, TestConstants {
    using CastU256I128 for uint256;

    event Point(bytes32 indexed param, address value);
    event SeriesMatured(uint256 chiAtMaturity);
    event Redeemed(address indexed from, address indexed to, uint256 amount, uint256 redeemed);
    event Transfer(address indexed src, address indexed dst, uint wad);

    Cauldron public cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    FYToken public fyDAI = FYToken(0xFCb9B8C5160Cf2999f9879D8230dCed469E72eeb);
    Join public daiJoin = Join(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc);
    FlashBorrower public borrower;

    address public timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes6 public ilkId = 0x303100000000; // For DAI
    bytes6 public seriesId = 0x303130370000; // ETH/DAI Dec 22 series
    bytes12 public vaultId;

    function setUp() public virtual {
        vm.createSelectFork('mainnet', 15266900);
        borrower = new FlashBorrower(fyDAI);
    }
}

abstract contract WithZeroFee is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        vm.prank(timelock);
        fyDAI.setFlashFeeFactor(0);
    }
}

abstract contract WithNonZeroFee is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        vm.prank(timelock);
        fyDAI.setFlashFeeFactor(WAD * 5 / 100);
    }
}

abstract contract AfterMaturity is WithZeroFee {
    function setUp() public override {
        super.setUp();
        vm.warp(1664550000);
    }
}

contract FYTokenFlashTest is ZeroState {
    function testFlashLoanDisabledByDefault() public {
        console.log("cannot do flash loan by default");
        vm.expectRevert("Cast overflow");                   // fee factor hasn't been set
        fyDAI.flashLoan(borrower, address(fyDAI), 1, bytes(hex"00"));
    }

}

contract WithZeroFeeTest is WithZeroFee {
    function testFlashBorrow() public {
        console.log("can do a simple flash borrow");
        borrower.flashBorrow(address(fyDAI), WAD, FlashBorrower.Action.NORMAL);
        assertEq(fyDAI.balanceOf(address(this)), 0);
        assertEq(borrower.flashBalance(), WAD);
        assertEq(borrower.flashToken(), address(fyDAI));
        assertEq(borrower.flashAmount(), WAD);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testRepayWithTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(fyDAI), address(0), WAD);
        borrower.flashBorrow(address(fyDAI), WAD, FlashBorrower.Action.TRANSFER);

        assertEq(fyDAI.balanceOf(address(this)), 0);
        assertEq(borrower.flashBalance(), WAD);
        assertEq(borrower.flashToken(), address(fyDAI));
        assertEq(borrower.flashAmount(), WAD);
        assertEq(borrower.flashFee(), 0);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testApproveNonInitiator() public {
        vm.expectRevert("ERC20: Insufficient approval");
        fyDAI.flashLoan(
            borrower, 
            address(fyDAI), 
            WAD, 
            bytes(abi.encode(0))
        );
    }

    function testEnoughFundsForLoanRepay() public {
        vm.expectRevert("ERC20: Insufficient balance");
        borrower.flashBorrow(address(fyDAI), WAD, FlashBorrower.Action.STEAL);
    }

    function testNestedFlashLoans() public {
        borrower.flashBorrow(address(fyDAI), WAD, FlashBorrower.Action.REENTER);
        assertEq(borrower.flashBalance(), WAD * 3);
    }
}

contract WithNonZeroFeeTest is WithNonZeroFee {
    function testFlashLoan() public {
        vm.prank(timelock);
        fyDAI.grantRole(fyDAI.mint.selector, address(this));
        fyDAI.mint(address(borrower), WAD * 5 / 100);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(borrower), address(0), WAD + (WAD * 5 / 100));
        borrower.flashBorrow(address(fyDAI), WAD, FlashBorrower.Action.NORMAL);
    }
}

contract AfterMaturityTest is AfterMaturity {
    function testNoFlashBorrowAfterMaturity() public {
        console.log("cannot flash borrow after maturity");
        vm.expectRevert("Only before maturity");
        borrower.flashBorrow(address(fyDAI), WAD, FlashBorrower.Action.NORMAL);
    }
}