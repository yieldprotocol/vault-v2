// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";
import "../../mocks/ERC20Mock.sol";
using CastU256I128 for uint256;
using CastI128U128 for int128;
contract VRLadleAdminTests is ZeroState {
    // @notice Test ability to set borrowing fee
    function testSetBorrowingFee() public {
        ladle.setFee(1000);
        assertEq(ladle.borrowingFee(), 1000);
    }
}

contract VRLadleJoinAdminTests is ZeroState {
    // @notice Test not able to add join before adding ilk
    function testNoAddJoinWithoutIlk() public {
        vm.expectRevert("Asset not found");
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
    }

    // @notice Test not able to add join with a mismatched ilk
    function testAddJoinMismatch() public {
        cauldron.addAsset(usdcId, address(usdc));
        vm.expectRevert("Mismatched asset and join");
        ladle.addJoin(usdcId, IJoin(address(daiJoin)));
    }

    // @notice Test ability to add join
    function testAddJoin() public {
        cauldron.addAsset(usdcId, address(usdc));
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
        assertEq(address(ladle.joins(usdcId)), address(usdcJoin));
    }

    // @notice Test the same join for a second ilk of the same asset
    function testAddJoinSameAsset() public {
        cauldron.addAsset(usdcId, address(usdc));
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
        cauldron.addAsset(otherIlkId, address(usdc));
        ladle.addJoin(otherIlkId, IJoin(address(usdcJoin)));
        assertEq(address(ladle.joins(usdcId)), address(usdcJoin));
        assertEq(address(ladle.joins(otherIlkId)), address(usdcJoin));
    }
}

contract VaultTests is VaultBuiltState {
    function testBuildVault() public {
        (bytes12 vaultId_, ) = ladle.build(baseId, usdcId, 123);
        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(vaultId_);
        assertEq(baseId_, baseId);
        assertEq(ilkId_, usdcId);
        assertEq(owner, address(this));
    }

    function testZeroIlkId() public {
        vm.expectRevert("Ilk id is zero");
        ladle.build(baseId, bytes6(0), 123);
    }

    function testTweakOnlyOwner() public {
        vm.expectRevert("Only vault owner");
        vm.prank(admin);
        ladle.tweak(vaultId, baseId, usdcId);
    }

    function testDestroyVault() public {
        vm.expectEmit(true, false, false, false);
        emit VaultDestroyed(vaultId);
        ladle.destroy(vaultId);
    }

    function testChangeVault() public {
        vm.expectEmit(true, true, true, false);
        emit VaultTweaked(vaultId, baseId, daiId);
        ladle.tweak(vaultId, baseId, daiId);

        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(vaultId);
        assertEq(baseId_, baseId);
        assertEq(ilkId_, daiId);
        assertEq(owner, address(this));
    }

    function testGiveVault() public {
        vm.expectEmit(true, true, false, false);
        emit VaultGiven(vaultId, admin);
        ladle.give(vaultId, admin);

        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(vaultId);
        assertEq(baseId_, baseId);
        assertEq(ilkId_, usdcId);
        assertEq(owner, admin);
    }

    function testOtherCantChangeOwnerOfVault() public {
        vm.expectRevert("Only vault owner");
        vm.prank(admin);
        ladle.give(vaultId, admin);
    }

    function testOnlyOwnerCouldMove() public {
        vm.prank(admin);
        vm.expectRevert("Only origin vault owner");
        ladle.stir(vaultId, otherVaultId, 1, 1);
    }

    function testOnlyDestinationVaultOwner() public {
        vm.prank(admin);
        vm.expectRevert("Only destination vault owner");
        ladle.stir(vaultId, otherVaultId, 0, 1);
    }
}

contract PourTests is VaultBuiltState {

    function setUp() public override{
        super.setUp();
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vaultId);
        IERC20 token = IERC20(cauldron.assets(ilkId));
        deal(address(token), address(this), INK);
        token.approve(address(ladle.joins(ilkId)),INK);
    }
    function testOnlyOwnerCanPour() public {
        vm.expectRevert("Only vault owner");
        vm.prank(admin);
        ladle.pour(vaultId, address(this), 1000, 1000);
    }

    function testPourToPostCollateral() public {
        
        ladle.pour(vaultId, address(this), 1000, 0);
    }

    function testPourToPostAndBorrow() public {
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vaultId);

        ladle.pour(vaultId, address(this), INK.i128(), ART.i128());
        assertEq(IERC20(cauldron.assets(baseId)).balanceOf(address(this)), ART);
    }

    function testPourToPostAndBorrowToOther() public {
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vaultId);

        ladle.pour(vaultId, admin, INK.i128(), ART.i128());
        assertEq(IERC20(cauldron.assets(baseId)).balanceOf(admin), ART);
    }
}

contract PouredStateTests is CauldronPouredState {

    function testPourToWithdraw() public {
        (, , bytes6 ilkId) = cauldron.vaults(vaultId);
        
        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(address(this)), 0);
        vm.expectEmit(true, true, true, true);
        emit VaultPoured(vaultId, baseId, ilkId, -(INK).i128(), 0);
        ladle.pour(vaultId, address(this), -(INK).i128(), 0);
        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(address(this)), INK);
        
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testPourToWithdrawToOther() public {
        (, , bytes6 ilkId) = cauldron.vaults(vaultId);
        
        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(address(this)), 0);
        vm.expectEmit(true, true, true, true);
        emit VaultPoured(vaultId, baseId, ilkId, -(INK).i128(), 0);
        ladle.pour(vaultId, admin, -(INK).i128(), 0);
        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(admin), INK);
        
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testCannotBorrowUnderLimit() public {
        vm.expectRevert("Min debt not reached");
        ladle.pour(vaultId, address(this), 0, 1);
    }

    function testPourToBorrowBase() public {
        ladle.pour(vaultId, address(this), 0, (ART).i128());
    }

    function testFeeChargeOnBorrow() public {
        ladle.setFee(FEE);
        ladle.pour(vaultId, address(this), 0, (ART).i128());

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, ART + FEE);
    }

    function testMoveDebt() public{
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (address owner, , bytes6 ilkId) = cauldron.vaults(vaultId);
        deal(cauldron.assets(ilkId), owner, INK);
        IERC20(cauldron.assets(ilkId)).approve(address(ladle.joins(ilkId)), INK);
        ladle.pour(otherVaultId, msg.sender, (INK).i128(), 0);
        ladle.pour(vaultId, address(this), 0, (ART).i128());
        
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, 0, art);
        ladle.stir(vaultId, otherVaultId, 0, art);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }

    function testMoveCollateral() public {
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        
        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, ink, 0);
        ladle.stir(vaultId, otherVaultId, ink, 0);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }

    function testMoveDebtAndCollateral() public {
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        ladle.pour(vaultId, address(this), 0, (ART).i128());
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        
        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, ink, art);
        ladle.stir(vaultId, otherVaultId, ink, art);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }

    function testMoveCollateralInABatch() public {
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(VRLadle.stir.selector, vaultId, otherVaultId, ink, 0);

        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, ink, 0);
        ladle.batch(calls);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }

    function testMoveDebtInABatch() public {
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (address owner, , bytes6 ilkId) = cauldron.vaults(vaultId);
        deal(cauldron.assets(ilkId), owner, INK);
        IERC20(cauldron.assets(ilkId)).approve(address(ladle.joins(ilkId)), INK);
        ladle.pour(otherVaultId, msg.sender, (INK).i128(), 0);
        ladle.pour(vaultId, address(this), 0, (ART).i128());

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(VRLadle.stir.selector, vaultId, otherVaultId, 0, ART);

        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, 0, uint128(ART));
        ladle.batch(calls);

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }
}

contract BorrowedStateTests is BorrowedState {
    IERC20 token;

    function setUp() public override {
        super.setUp();
        (, bytes6 baseId, ) = cauldron.vaults(vaultId);
        token = IERC20(cauldron.assets(baseId));
    }
    function testRepayDebt() public {
        token.approve(address(ladle.joins(baseId)), ART);
        ladle.pour(vaultId, address(this), 0, -(ART.i128()));

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testRepayDebtWithTransfer() public {
        token.transfer(address(ladle.joins(baseId)), ART);
        ladle.pour(vaultId, admin, 0, -(ART).i128());

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testCantRepayMoreThanDebt() public {
        token.approve(address(ladle.joins(baseId)), ART + 10);
        vm.expectRevert("Result below zero");
        ladle.pour(vaultId, admin, 0, -(ART + 10).i128());
    }

    function testBorrowWhileUnderGlobalDebtLimit() public {
        ladle.pour(vaultId, address(this), 0, (ART).i128());
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, ART * 2);
    }

    function testCantBorrowOverGlobalDebtLimit() public {
        vm.expectRevert("Max debt exceeded");
        ladle.pour(vaultId, address(this), 0, (ART * 20 * 1e6).i128());
    }
}