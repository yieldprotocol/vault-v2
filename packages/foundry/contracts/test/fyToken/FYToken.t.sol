// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "../../Cauldron.sol";
import "../../FYToken.sol";
import "../../Join.sol";
import "../../interfaces/IJoin.sol";
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

    Cauldron public cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    FYToken public fyDAI = FYToken(0xFCb9B8C5160Cf2999f9879D8230dCed469E72eeb);
    Join public daiJoin = Join(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc);

    address public timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes6 public ilkId = 0x303100000000; // For DAI
    bytes6 public seriesId = 0x303130370000; // ETH/DAI Dec 22 series
    bytes12 public vaultId;

    function setUp() public virtual {
        vm.createSelectFork('mainnet', 15266900);

        vm.startPrank(timelock);
        bytes4[] memory fyTokenRoles = new bytes4[](2);
        fyTokenRoles[0] = fyDAI.mint.selector;
        fyTokenRoles[1] = fyDAI.point.selector;
        fyDAI.grantRoles(fyTokenRoles, address(this));
        vm.stopPrank();

        (vaultId, ) = ladle.build(seriesId, ilkId, 0);                  // create vault
        deal(dai, address(this), WAD * 1);                              // populate the test address/vault owner with 1 DAI
        IERC20(dai).approve(address(daiJoin), WAD);         
        ladle.pour(vaultId, address(this), WAD.i128(), WAD.i128());     // add ink and art to vault, will mint 1 fyDAI

        
        deal(dai, address(this), WAD * 2);                              // populate the test address/vault owner with 2 DAI
        IERC20(dai).approve(address(daiJoin), WAD * 2);
        vm.prank(address(ladle));
        daiJoin.join(address(this), uint128(WAD * 2));                  // Join takes the 2 DAI
    }
}

abstract contract AfterMaturity is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        vm.warp(1664550000);
    }
}

abstract contract OnceMatured is AfterMaturity {
    CTokenChiMock public chiOracle;
    uint256 accrual = FullMath.mulDiv(WAD, 110, 100);                       // 10%

    function setUp() public override {
        super.setUp();
        chiOracle = new CTokenChiMock();
        fyDAI.mature();
        fyDAI.point("oracle", address(chiOracle));                          // Uses new oracle to update to new chi value
        chiOracle.set(220434062002504964823286680 * 110 / 100);             // Will set chi returned to be 10% 
    }
}

contract FYTokenTest is ZeroState {
    function testChangeOracle() public {
        console.log("can change the CHI oracle");
        vm.prank(timelock);
        vm.expectEmit(true, false, false, true);
        emit Point("oracle", address(this));
        fyDAI.point("oracle", address(this));
    }

    function testChangeJoin() public {
        console.log("can change Join");
        vm.prank(timelock);
        vm.expectEmit(true, false, false, true);
        emit Point("join", address(this));
        fyDAI.point("join", address(this));
    }

    function testMintWithUnderlying() public {
        console.log("can mint with underlying");
        uint256 balance = fyDAI.balanceOf(address(this));   // will have 1 fyDAI
        fyDAI.mint(address(this), WAD);
        assertEq(fyDAI.balanceOf(address(this)) - balance, WAD);
    }

    function testCantMatureBeforeMaturity() public {
        console.log("can't mature before maturity");
        vm.prank(timelock);
        vm.expectRevert("Only after maturity");
        fyDAI.mature();
    }

    function testCantRedeemBeforeMaturity() public {
        console.log("can't redeem before maturity");
        vm.expectRevert("Only after maturity");
        fyDAI.redeem(address(this), WAD);
    }

    function testConvertToPrincipal() public {
        console.log("can convert amount of underlying to principal");
        assertEq(fyDAI.convertToPrincipal(1000), 1000);
    }

    function testConvertToUnderlying() public {
        console.log("can convert amount of principal to underlying");
        assertEq(fyDAI.convertToUnderlying(1000), 1000);
    }
}

contract AfterMaturityTest is AfterMaturity {
    function testCantMintAfterMaturity() public {
        console.log("can't mint after maturity");
        vm.expectRevert("Only before maturity");
        fyDAI.mint(address(this), WAD);
    }

    function testMatureOnlyOnce() public {
        console.log("can only mature once");
        vm.prank(timelock);
        fyDAI.mature();
        vm.expectRevert("Already matured");
        fyDAI.mature();
    }

    function testMatureRecordsChiValue() public {
        console.log("records chi value when matureed");
        vm.prank(timelock);
        vm.expectEmit(false, false, false, true);
        emit SeriesMatured(220434062002504964823286680);
        fyDAI.mature();
    }

    function testMaturesFirstRedemptionAfterMaturity() public {
        console.log("matures on first redemption after maturity if needed");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this), 
            address(this), 
            WAD, 
            WAD
        );
        fyDAI.redeem(address(this), WAD);
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + WAD
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - WAD
        );
        assertEq(
            fyDAI.balanceOf(address(this)), 
            0
        );
    }
}

contract OnceMaturedTest is OnceMatured {
    function testChiAccrualNotBelowOne() public {
        console.log("cannot have chi accrual below 1");
        assertGt(fyDAI.accrual(), WAD);
    }

    function testPreviewRedeem() public {
        console.log("can preview the amount of underlying redeemed");
    }

    function testMaxRedeem() public {
        console.log("can get the max amount of principal redeemable");
    }

    function testPreviewWithdraw() public {
        console.log("can preview the amount of principal withdrawn");
    }

    function testMaxWithdraw() public {
        console.log("can get the max amount of underlying withdrawable");
    }

    function testRedeemWithAccrual() public {
        console.log("redeems according to chi accrual");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this), 
            address(this), 
            WAD, 
            FullMath.mulDiv(WAD, accrual, WAD)
        );
        fyDAI.redeem(address(this), WAD);
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            fyDAI.balanceOf(address(this)), 
            0
        );
    }

    function testRedeemOnTransfer() public {
        console.log("redeems when transfering to the fyToken contract");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        fyDAI.transfer(address(fyDAI), WAD);
        assertEq(fyDAI.balanceOf(address(this)), 0);
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this),
            address(this), 
            WAD, 
            FullMath.mulDiv(WAD, accrual, WAD)
        );
        fyDAI.redeem(address(this), 0);
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );
    }
}