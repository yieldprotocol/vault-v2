// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "../../Cauldron.sol";
import "../../FYToken.sol";
import "../../Join.sol";
import "../../interfaces/IJoin.sol";
import "../../interfaces/ILadle.sol";
import "../../interfaces/IOracle.sol";
import "../../oracles/uniswap/uniswapv0.8/FullMath.sol";
import "../../mocks/oracles/compound/CTokenChiMock.sol";
import "../../mocks/FlashBorrower.sol";
import "../utils/TestConstants.sol";

interface ILadleCustom {
    function addToken(address token, bool set) external;

    function batch(bytes[] calldata calls) external payable returns(bytes[] memory results);

    function transfer(IERC20 token, address receiver, uint128 wad) external payable;

    function redeem(bytes6 seriesId, address to, uint256 wad) external payable returns (uint256);
}

abstract contract ZeroState is Test, TestConstants {
    using CastU256I128 for uint256;

    event Point(bytes32 indexed param, address value);
    event SeriesMatured(uint256 chiAtMaturity);
    event Redeemed(address indexed from, address indexed to, uint256 amount, uint256 redeemed);

    FYToken public fyDAI;
    Cauldron public cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    // FYToken public fyDAI = FYToken(0xFCb9B8C5160Cf2999f9879D8230dCed469E72eeb);
    Join public daiJoin = Join(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc);

    address public timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes6 public ilkId = 0x303100000000; // For DAI
    bytes6 public seriesId = 0x303130390000; // ETH/DAI March 23 series
    bytes12 public vaultId;

    function setUp() public virtual {
        vm.createSelectFork('mainnet', 15266900);
        vm.startPrank(timelock);

        fyDAI = new FYToken(
            DAI,
            IOracle(0x53FBa816BD69a7f2a096f58687f87dd3020d0d5c), // Compound oracle
            daiJoin,
            1664550000,
            "FYDAI2209",
            "FYDAI2209"
        );

        bytes4[] memory fyTokenRoles = new bytes4[](2);
        fyTokenRoles[0] = fyDAI.mint.selector;
        fyTokenRoles[1] = fyDAI.point.selector;
        fyDAI.grantRoles(fyTokenRoles, address(this));
        fyDAI.grantRoles(fyTokenRoles, address(ladle));

        bytes4[] memory daiJoinRoles = new bytes4[](2);
        daiJoinRoles[0] = daiJoin.join.selector;
        daiJoinRoles[1] = daiJoin.exit.selector;
        daiJoin.grantRoles(daiJoinRoles, address(fyDAI));

        ILadleCustom(address(ladle)).addToken(address(fyDAI), true);
        cauldron.addSeries(seriesId, 0x303100000000, fyDAI);
        bytes6[] memory ilkIds = new bytes6[](1);
        ilkIds[0] = ilkId;
        cauldron.addIlks(seriesId, ilkIds);

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
    address fyTokenHolder = address(1);

    function setUp() public override {
        super.setUp();
        chiOracle = new CTokenChiMock();
        fyDAI.point("oracle", address(chiOracle));                          // Uses new oracle to update to new chi value
        chiOracle.set(220434062002504964823286680); 
        fyDAI.mature();
        chiOracle.set(220434062002504964823286680 * 110 / 100);             // Will set chi returned to be 10%
    }
}

contract FYTokenTest is ZeroState {
    function testChangeOracle() public {
        console.log("can change the CHI oracle");
        vm.expectEmit(true, false, false, true);
        emit Point("oracle", address(this));
        fyDAI.point("oracle", address(this));
    }

    function testChangeJoin() public {
        console.log("can change Join");
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

    function testPreviewRedeem() public {
        console.log("can preview the amount of underlying redeemed");
        assertEq(fyDAI.previewRedeem(WAD), WAD);
    }

    function testPreviewWithdraw() public {
        console.log("can preview the amount of principal withdrawn");
        assertEq(fyDAI.previewWithdraw(WAD), WAD);
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

    function testMatureRevertsOnZeroChi() public {
        console.log("can't mature if chi is zero");

        CTokenChiMock chiOracle = new CTokenChiMock(); // Use a new oracle that we can force to be zero
        fyDAI.mature();
        fyDAI.point("oracle", address(chiOracle));
        chiOracle.set(0); 

        vm.prank(timelock);
        fyDAI.mature();
        vm.expectRevert("Chi oracle malfunction");
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
    function testCannotChangeOracle() public {
        console.log("can't change the CHI oracle once matured");
        vm.expectRevert("Already matured");
        fyDAI.point("oracle", address(this));
    }

    function testChiAccrualNotBelowOne() public {
        console.log("cannot have chi accrual below 1");
        assertGt(fyDAI.accrual(), WAD);
    }

    function testConvertToUnderlyingWithAccrual() public {
        console.log("can convert the amount of underlying plus the accrual to principal");
        assertEq(fyDAI.convertToUnderlying(1000), 1100);
        assertEq(fyDAI.convertToUnderlying(5000), 5500);
    }

    function testConvertToPrincipalWithAccrual() public {
        console.log("can convert the amount of underlying plus the accrual to principal");
        assertEq(fyDAI.convertToPrincipal(1100), 1000);
        assertEq(fyDAI.convertToPrincipal(5500), 5000);
    }

    function testMaxRedeem() public {
        console.log("can get the max amount of principal redeemable");
        deal(address(fyDAI), address(this), WAD * 2);
        assertEq(fyDAI.maxRedeem(address(this)), WAD * 2);
    }

    function testMaxWithdraw() public {
        console.log("can get the max amount of underlying withdrawable");
        deal(address(fyDAI), address(this), WAD * 2);
        assertEq(fyDAI.maxRedeem(address(this)), WAD * 2);
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
        fyDAI.redeem(address(this), WAD);
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );
    }

    function testRedeemByTransferAndApprove() public {
        console.log("redeems by transfer and approve combination");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        fyDAI.transfer(address(fyDAI), WAD / 2);
        assertEq(fyDAI.balanceOf(address(this)), WAD / 2);
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this), 
            address(this), 
            WAD,
            FullMath.mulDiv(WAD, accrual, WAD)
        );
        fyDAI.redeem(WAD, address(this), address(this));
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );        
    }

    function testRedeemByBatch() public {
        console.log("redeems by transferring to the fyToken contract in a batch");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        fyDAI.approve(address(ladle), WAD);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(ILadleCustom(address(ladle)).transfer.selector, address(fyDAI), address(fyDAI), WAD);
        calls[1] = abi.encodeWithSelector(ILadleCustom(address(ladle)).redeem.selector, seriesId, address(this), WAD);
        ILadleCustom(address(ladle)).batch(calls);
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );
    }

    function testRedeemByBatchWithZeroAmount() public {
        console.log("redeems with an amount of 0 by transferring to the fyToken contract in a batch");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        fyDAI.approve(address(ladle), WAD);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(ILadleCustom(address(ladle)).transfer.selector, address(fyDAI), address(fyDAI), WAD);
        calls[1] = abi.encodeWithSelector(ILadleCustom(address(ladle)).redeem.selector, seriesId, address(this), 0);
        ILadleCustom(address(ladle)).batch(calls);
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );
    }

    function testRedeemERC5095() public {
        console.log("redeems with ERC5095 redeem");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this), 
            address(this), 
            WAD, 
            FullMath.mulDiv(WAD, accrual, WAD)
        );
        fyDAI.redeem(WAD, address(this), address(this));
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );        
    }

    function testRedeemWithZeroAmount() public {
        console.log("Redeems the contract's balance when amount is 0");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        deal(address(fyDAI), address(fyDAI), WAD * 10);

        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this), 
            address(this), 
            WAD * 10, 
            FullMath.mulDiv(WAD * 10, accrual, WAD)
        );
        fyDAI.redeem(0, address(this), address(this));
        assertEq(
            fyDAI.balanceOf(address(fyDAI)), 
            0
        );
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD * 10, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)),
            joinBalanceBefore - FullMath.mulDiv(WAD * 10, accrual, WAD)
        );
    }

    function testRedeemApproval() public {
        console.log("can redeem only the approved amount from holder");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        deal(address(fyDAI), fyTokenHolder, WAD * 5);
        vm.prank(fyTokenHolder);
        fyDAI.approve(address(this), WAD * 5);

        vm.expectRevert("ERC20: Insufficient approval");
        fyDAI.redeem(
            WAD * 10, 
            address(this), 
            fyTokenHolder
        );

        fyDAI.redeem(
            WAD * 4,
            address(this),
            fyTokenHolder
        );
        assertEq(fyDAI.balanceOf(fyTokenHolder), WAD);
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD * 4, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)),
            joinBalanceBefore - FullMath.mulDiv(WAD * 4, accrual, WAD)
        );
    }

    function testWithdrawERC5095() public {
        console.log("withdrwas with ERC5095 withdraw");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this), 
            address(this), 
            WAD, 
            FullMath.mulDiv(WAD, accrual, WAD)
        );
        fyDAI.withdraw(FullMath.mulDiv(WAD, accrual, WAD), address(this), address(this));
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)), 
            joinBalanceBefore - FullMath.mulDiv(WAD, accrual, WAD)
        );
    }

    function testWithdrawWithZeroAmount() public {
        console.log("Withdraws the contract's balance when amount is 0");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        deal(address(fyDAI), address(fyDAI), WAD * 10);

        vm.expectEmit(true, true, false, true);
        emit Redeemed(
            address(this), 
            address(this), 
            WAD * 10, 
            FullMath.mulDiv(WAD * 10, accrual, WAD)
        );
        fyDAI.withdraw(0, address(this), address(this));
        assertEq(
            fyDAI.balanceOf(address(fyDAI)), 
            0
        );
        assertEq(
            IERC20(dai).balanceOf(address(this)), 
            ownerBalanceBefore + FullMath.mulDiv(WAD * 10, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)),
            joinBalanceBefore - FullMath.mulDiv(WAD * 10, accrual, WAD)
        );
    }

    function testWithdrawApproval() public {
        console.log("can withdraw only the approved amount from holder");
        uint256 ownerBalanceBefore = IERC20(dai).balanceOf(address(this));
        uint256 joinBalanceBefore = IERC20(dai).balanceOf(address(daiJoin));
        deal(address(fyDAI), fyTokenHolder, WAD * 5);
        vm.prank(fyTokenHolder);
        fyDAI.approve(address(this), WAD * 5);

        uint256 amountToWithdraw = fyDAI.convertToUnderlying(WAD * 10);     // so revert works properly
        vm.expectRevert("ERC20: Insufficient approval");
        fyDAI.withdraw(
            amountToWithdraw,
            address(this),
            fyTokenHolder
        );

        fyDAI.withdraw(
            fyDAI.convertToUnderlying(WAD * 4),
            address(this),
            fyTokenHolder
        );
        assertEq(fyDAI.balanceOf(fyTokenHolder), WAD);
        assertEq(
            IERC20(dai).balanceOf(address(this)),
            ownerBalanceBefore + FullMath.mulDiv(WAD * 4, accrual, WAD)
        );
        assertEq(
            IERC20(dai).balanceOf(address(daiJoin)),
            joinBalanceBefore - FullMath.mulDiv(WAD * 4, accrual, WAD)
        );
    }
}