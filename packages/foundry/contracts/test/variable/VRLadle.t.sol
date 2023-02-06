// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";
import "../../mocks/ERC20Mock.sol";
using CastU256I128 for uint256;

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
}

contract BorrowedStateTests is BorrowedState {
    IERC20 token;
    function testRepayDebt() public {
        ladle.pour(vaultId, address(this), 0, -(ART).i128());
        (, bytes6 baseId, ) = cauldron.vaults(vaultId);
        token = IERC20(cauldron.assets(baseId));
    }

    function testRepayDebtWithTransfer() public {
        (, bytes6 baseId, ) = cauldron.vaults(vaultId);

        token.transfer(address(ladle.joins(baseId)), ART);
        ladle.pour(vaultId, admin, 0, -(ART).i128());
    }

    function testCantRepayMoreThanDebt() public {
        ladle.pour(vaultId, admin, 0, -(ART + 10).i128());
    }

    function testCantBorrowOverGlobalDebtLimit() public {

    }
}