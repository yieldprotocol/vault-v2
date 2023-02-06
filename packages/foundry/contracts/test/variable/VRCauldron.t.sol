// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";
using CastU256I128 for uint256;

contract AssetAndBaseAdditionTests is ZeroState {
    function testZeroIdentifier() public {
        vm.expectRevert("Asset id is zero");
        cauldron.addAsset(0x000000000000, address(base));
    }

    function testAddAsset() public {
        cauldron.addAsset(usdcId, address(usdc));
        assertEq(cauldron.assets(usdcId), address(usdc));
    }

    function testBaseAdditionFail() public {
        vm.expectRevert("Base not found");
        cauldron.addBase(otherIlkId);
    }

    function testBaseAdditionFail2() public {
        cauldron.addAsset(usdcId, address(usdc));
        vm.expectRevert("Rate oracle not found");
        cauldron.addBase(usdcId);
    }

    function testBaseAddition() public {
        cauldron.addAsset(usdcId, address(usdc));
        cauldron.setRateOracle(usdcId, IOracle(address(chiRateOracle)));
        cauldron.addBase(usdcId);
        assertEq(cauldron.bases(usdcId), true);
    }
}

contract AssetAndIlkAddedTests is AssetAddedState {
    function testSameIdentifier() public {
        vm.expectRevert("Id already used");
        cauldron.addAsset(usdcId, address(usdc));
    }

    function testAddSameAssetWithDifferentId() public {
        cauldron.addAsset(otherIlkId, address(usdc));
        assertEq(cauldron.assets(otherIlkId), address(usdc));
    }

    function testDebtLimitForUnknownBase() public {
        vm.expectRevert("Base not found");
        cauldron.setDebtLimits(otherIlkId, usdcId, 0, 0, 0);
    }

    function testDebtLimitForUnknownIlk() public {
        vm.expectRevert("Ilk not found");
        cauldron.setDebtLimits(baseId, otherIlkId, 0, 0, 0);
    }

    function testSetDebtLimits() public {
        cauldron.setDebtLimits(baseId, usdcId, 2, 1, 3);
        (uint96 max, uint24 min, uint8 dec, ) = cauldron.debt(baseId, usdcId);
        assertEq(min, 1);
        assertEq(max, 2);
        assertEq(dec, 3);
    }

    function testAddRateOracle() public {
        cauldron.setRateOracle(usdcId, IOracle(address(spotOracle)));
        assertEq(address(cauldron.rateOracles(usdcId)), address(spotOracle));
    }
}

contract IlkAddition is IlkAddedState {
    function testCannotAddIlkWithoutSpotOracle() public {
        vm.expectRevert("Spot oracle not found");
        cauldron.addIlks(baseId, ilkIds);
    }

    function testCannotAddIlkOnUnknownBase() public {
        vm.expectRevert("Base not found");
        cauldron.addIlks(otherIlkId, ilkIds);
    }

    function testAddIlkAndSpotOracle() public {
        cauldron.setSpotOracle(baseId, usdcId, spotOracle, 1000000);
        cauldron.setSpotOracle(baseId, daiId, spotOracle, 1000000);
        (IOracle oracle, ) = cauldron.spotOracles(baseId, usdcId);
        assertEq(address(oracle), address(spotOracle));

        cauldron.addIlks(baseId, ilkIds);
        assertEq(cauldron.ilks(baseId, usdcId), true);
    }
}

contract OracleAddition is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        ilkIds = new bytes6[](1);
        ilkIds[0] = usdcId;
    }

    function testNotAllowedToAddRateOracleForUnknownBase() public {
        vm.expectRevert("Base not found");
        cauldron.setRateOracle(otherIlkId, IOracle(address(chiRateOracle)));
    }

    function testNotAllowedToAddSpotOracleForUnknownBase() public {
        vm.expectRevert("Base not found");
        cauldron.setSpotOracle(
            otherIlkId,
            usdcId,
            IOracle(address(spotOracle)),
            10
        );
    }

    function testNotAllowedToAddSpotOracleForUnknownIlk() public {
        vm.expectRevert("Ilk not found");
        cauldron.setSpotOracle(
            baseId,
            otherIlkId,
            IOracle(address(spotOracle)),
            10
        );
    }
}

contract VaultTest is RateOracleAddedState {
    function testNoZeroVaultId() public {
        vm.expectRevert("Vault id is zero");
        cauldron.build(address(this), zeroVaultId, baseId, usdcId);
    }

    function testNoZeroBaseIdVault() public {
        vm.expectRevert("Base id is zero");
        cauldron.build(address(this), vaultId, zeroId, usdcId);
    }

    function testNoZeroIlkIdVault() public {
        vm.expectRevert("Ilk id is zero");
        cauldron.build(address(this), vaultId, baseId, zeroId);
    }

    function testIlkNotAdded() public {
        vm.expectRevert("Ilk not added to base");
        cauldron.build(address(this), vaultId, baseId, usdcId);
    }
}

contract CauldronBuildTest is CompleteSetup {
    function testVaultBuild() public {
        cauldron.build(address(this), vaultId, baseId, usdcId);
        (
            address owner_,
            bytes6 baseId_, // Each vault is related to only one series, which also determines the underlying.
            bytes6 ilkId_
        ) = cauldron.vaults(vaultId);
        assertEq(owner_, address(this));
        assertEq(baseId_, baseId);
        assertEq(ilkId_, usdcId);
    }
}

contract CauldronTestOnBuiltVault is VaultBuiltState {
    function testVaultBuildingWithSameIdFails() public {
        vm.expectRevert("Vault already exists");
        cauldron.build(address(this), vaultId, baseId, usdcId);
    }

    function testVaultDestroy() public {
        cauldron.destroy(vaultId);
        (address owner_, , ) = cauldron.vaults(vaultId);
        assertEq(owner_, address(0));
    }

    function testPour() public {
        cauldron.pour(
            vaultId,
            INK.i128(),
            ART.i128()
        );
    }

    function testGiveVault() public {
        cauldron.give(vaultId, user);
        (address owner_, , ) = cauldron.vaults(vaultId);
        assertEq(owner_, user);
    }

    function testChangeVault() public {
        cauldron.tweak(vaultId, baseId, daiId);
        (, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(vaultId);
        assertEq(baseId_, baseId);
        assertEq(ilkId_, daiId);
    }

    function testCannotTweakVaultWithCollateral() public {
        cauldron.pour(vaultId, INK.i128(), 0);
        vm.expectRevert("Only with no collateral");
        cauldron.tweak(vaultId, baseId, daiId);
    }

    function testCannotTweakVaultWithDebt() public {
        cauldron.pour(
            vaultId,
            INK.i128(),
            ART.i128()
        );

        // Adding new base and ilks to it
        chiRateOracle.setSource(daiId, RATE, WAD, WAD * 2);
        chiRateOracle.setSource(daiId, CHI, WAD, WAD * 2);
        makeBase(daiId, address(dai), daiJoin, address(chiRateOracle), 12);
        cauldron.setSpotOracle(daiId, usdcId, spotOracle, 1000000);
        cauldron.addIlks(daiId, ilkIds);

        vm.expectRevert("Only with no debt");
        cauldron.tweak(vaultId, daiId, usdcId);
    }

    function testCannotTweakWithNotAddedToBase() public {
        vm.expectRevert("Ilk not added to base");
        cauldron.tweak(vaultId, baseId, otherIlkId);
    }
}

contract CauldronStirTests is CauldronPouredState {
    function testCannotMoveFromSameVault() public {
        vm.expectRevert("Identical vaults");
        cauldron.stir(vaultId, vaultId, 0, 0);
    }

    function testCannotMoveToUnitializedVault() public {
        vm.expectRevert("Vault not found");
        cauldron.stir(vaultId, otherVaultId, 0, 0);
    }

    function testDifferentCollateral() public {
        cauldron.build(address(this), otherVaultId, baseId, daiId);
        vm.expectRevert("Different collateral");
        cauldron.stir(vaultId, otherVaultId, 10, 0);
    }

    function testUndercollateralizedAtDestination() public {
        cauldron.pour(vaultId, 0, ART.i128());
        cauldron.build(address(this), otherVaultId, baseId, daiId);
        vm.expectRevert("Undercollateralized at destination");
        cauldron.stir(vaultId, otherVaultId, 0, 10);
    }

    function testMoveCollateral() public {
        cauldron.build(address(this), otherVaultId, baseId, usdcId);
        vm.expectEmit(true, true, false, true);
        emit VaultStirred(vaultId, otherVaultId, 10, 0);
        cauldron.stir(vaultId, otherVaultId, 10, 0);
    }

    function testMoveDebt() public {
        cauldron.pour(vaultId, 0, ART.i128());
        cauldron.build(address(this), otherVaultId, baseId, daiId);
        cauldron.pour(otherVaultId, INK.i128(), 0);
        vm.expectEmit(true, true, false, true);
        emit VaultStirred(vaultId, otherVaultId, 0, 10);
        cauldron.stir(vaultId, otherVaultId, 0, 10);
    }

    function testUndercollateralizedAtOrigin() public {
        cauldron.pour(vaultId, 0, ART.i128());
        cauldron.build(address(this), otherVaultId, baseId, usdcId);
        vm.expectRevert("Undercollateralized at origin");
        cauldron.stir(vaultId, otherVaultId, uint128(INK), 0);
    }
}
