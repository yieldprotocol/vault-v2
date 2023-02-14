// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";
using CastU256I128 for uint256;
using CastU256U128 for uint256;
using CastI128U128 for int128;

contract AssetAndBaseAdditionTests is ZeroState {
    function testZeroIdentifier() public {
        console.log('cannot add asset with zero identifier');
        vm.expectRevert("Asset id is zero");
        cauldron.addAsset(0x000000000000, address(base));
    }

    function testAddAsset() public {
        console.log('can add asset');
        cauldron.addAsset(usdcId, address(usdc));
        assertEq(cauldron.assets(usdcId), address(usdc));
    }

    function testBaseAdditionFail() public {
        console.log('cannot add base without asset being added first');
        vm.expectRevert("Base not found");
        cauldron.addBase(otherIlkId);
    }

    function testBaseAdditionFail2() public {
        console.log('cannot add base without rate oracle being set');
        cauldron.addAsset(usdcId, address(usdc));
        vm.expectRevert("Rate oracle not found");
        cauldron.addBase(usdcId);
    }

    function testBaseAddition() public {
        console.log('can add base');
        cauldron.addAsset(usdcId, address(usdc));
        cauldron.setRateOracle(usdcId, IOracle(address(chiRateOracle)));
        cauldron.addBase(usdcId);
        assertEq(cauldron.bases(usdcId), true);
    }
}

contract AssetAndIlkAddedTests is AssetAddedState {
    function testSameIdentifier() public {
        console.log('cannot add asset with same identifier');
        vm.expectRevert("Id already used");
        cauldron.addAsset(usdcId, address(usdc));
    }

    function testAddSameAssetWithDifferentId() public {
        console.log("can add asset with different identifier");
        cauldron.addAsset(otherIlkId, address(usdc));
        assertEq(cauldron.assets(otherIlkId), address(usdc));
    }

    function testDebtLimitForUnknownBase() public {
        console.log("cannot set debt limit for unknown base");
        vm.expectRevert("Base not found");
        cauldron.setDebtLimits(otherIlkId, usdcId, 0, 0, 0);
    }

    function testDebtLimitForUnknownIlk() public {
        console.log("cannot set debt limit for unknown ilk");
        vm.expectRevert("Ilk not found");
        cauldron.setDebtLimits(baseId, otherIlkId, 0, 0, 0);
    }

    function testSetDebtLimits() public {
        console.log("can set debt limits");
        cauldron.setDebtLimits(baseId, usdcId, 2, 1, 3);
        (uint96 max, uint24 min, uint8 dec, ) = cauldron.debt(baseId, usdcId);
        assertEq(min, 1);
        assertEq(max, 2);
        assertEq(dec, 3);
    }

    function testAddRateOracle() public {
        console.log("can add rate oracle");
        cauldron.setRateOracle(usdcId, IOracle(address(spotOracle)));
        assertEq(address(cauldron.rateOracles(usdcId)), address(spotOracle));
    }
}

contract IlkAddition is IlkAddedState {
    function testCannotAddIlkWithoutSpotOracle() public {
        console.log("cannot add ilk without spot oracle");
        vm.expectRevert("Spot oracle not found");
        cauldron.addIlks(baseId, ilkIds);
    }

    function testCannotAddIlkOnUnknownBase() public {
        console.log("cannot add ilk on unknown base");
        vm.expectRevert("Base not found");
        cauldron.addIlks(otherIlkId, ilkIds);
    }

    function testAddIlkAndSpotOracle() public {
        console.log("can add ilk and spot oracle");
        cauldron.setSpotOracle(baseId, usdcId, spotOracle, 1000000);
        cauldron.setSpotOracle(baseId, daiId, spotOracle, 1000000);
        cauldron.setSpotOracle(baseId, wethId, spotOracle, 1000000);
        (IOracle oracle, ) = cauldron.spotOracles(baseId, usdcId);
        assertEq(address(oracle), address(spotOracle));

        cauldron.addIlks(baseId, ilkIds);
        assertEq(cauldron.ilks(baseId, usdcId), true);
    }
}

contract OracleAddition is ZeroState {
    
    function testNotAllowedToAddRateOracleForUnknownBase() public {
        console.log("cannot add rate oracle for unknown base");
        vm.expectRevert("Base not found");
        cauldron.setRateOracle(otherIlkId, IOracle(address(chiRateOracle)));
    }

    function testNotAllowedToAddSpotOracleForUnknownBase() public {
        console.log("cannot add spot oracle for unknown base");
        vm.expectRevert("Base not found");
        cauldron.setSpotOracle(
            otherIlkId,
            usdcId,
            IOracle(address(spotOracle)),
            10
        );
    }

    function testNotAllowedToAddSpotOracleForUnknownIlk() public {
        console.log("cannot add spot oracle for unknown ilk");
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
        console.log("cannot build vault with zero vault id");
        vm.expectRevert("Vault id is zero");
        cauldron.build(address(this), zeroVaultId, baseId, usdcId);
    }

    function testNoZeroBaseIdVault() public {
        console.log("cannot build vault with zero base id");
        vm.expectRevert("Base id is zero");
        cauldron.build(address(this), vaultId, zeroId, usdcId);
    }

    function testNoZeroIlkIdVault() public {
        console.log("cannot build vault with zero ilk id");
        vm.expectRevert("Ilk id is zero");
        cauldron.build(address(this), vaultId, baseId, zeroId);
    }

    function testIlkNotAdded() public {
        console.log("cannot build vault with ilk which is not added to base");
        vm.expectRevert("Ilk not added to base");
        cauldron.build(address(this), vaultId, baseId, usdcId);
    }
}

contract CauldronBuildTest is CompleteSetup {
    function testVaultBuild() public {
        console.log("can build vault");
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
        console.log("cannot build vault with same id");
        vm.expectRevert("Vault already exists");
        cauldron.build(address(this), vaultId, baseId, usdcId);
    }

    function testVaultDestroy() public {
        console.log("can destroy vault");
        cauldron.destroy(vaultId);
        (address owner_, , ) = cauldron.vaults(vaultId);
        assertEq(owner_, address(0));
    }

    function testPour() public {
        console.log("can pour into a vault");
        cauldron.pour(
            vaultId,
            INK.i128(),
            ART.i128()
        );

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, uint128(INK));
        assertEq(art, uint128(ART));
    }

    function testGiveVault() public {
        console.log("can give vault");
        cauldron.give(vaultId, user);
        (address owner_, , ) = cauldron.vaults(vaultId);
        assertEq(owner_, user);
    }

    function testChangeVault() public {
        console.log("can tweak vault");
        cauldron.tweak(vaultId, baseId, daiId);
        (, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(vaultId);
        assertEq(baseId_, baseId);
        assertEq(ilkId_, daiId);
    }

    function testCannotTweakVaultWithCollateral() public {
        console.log("cannot tweak vault with collateral");
        cauldron.pour(vaultId, INK.i128(), 0);
        vm.expectRevert("Only with no collateral");
        cauldron.tweak(vaultId, baseId, daiId);
    }

    function testCannotTweakVaultWithDebt() public {
        console.log("cannot tweak vault with debt");
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
        cauldron.setSpotOracle(daiId, wethId, spotOracle, 1000000);
        cauldron.addIlks(daiId, ilkIds);

        vm.expectRevert("Only with no debt");
        cauldron.tweak(vaultId, daiId, usdcId);
    }

    function testCannotTweakWithNotAddedToBase() public {
        console.log("cannot tweak vault with ilk which is not added to base");
        vm.expectRevert("Ilk not added to base");
        cauldron.tweak(vaultId, baseId, otherIlkId);
    }
}

contract CauldronStirTests is CauldronPouredState {
    function testCannotMoveFromSameVault() public {
        console.log("cannot stir into same vault");
        vm.expectRevert("Identical vaults");
        cauldron.stir(vaultId, vaultId, 0, 0);
    }

    function testCannotMoveToUnitializedVault() public {
        console.log("cannot stir into unitialized vault");
        vm.expectRevert("Vault not found");
        cauldron.stir(vaultId, otherVaultId, 0, 0);
    }

    function testDifferentCollateral() public {
        console.log("cannot stir into vault with different collateral");
        cauldron.build(address(this), otherVaultId, baseId, daiId);
        vm.expectRevert("Different collateral");
        cauldron.stir(vaultId, otherVaultId, 10, 0);
    }

    function testUndercollateralizedAtDestination() public {
        console.log("cannot stir into vault with undercollateralized destination");
        cauldron.pour(vaultId, 0, ART.i128());
        cauldron.build(address(this), otherVaultId, baseId, daiId);
        vm.expectRevert("Undercollateralized at destination");
        cauldron.stir(vaultId, otherVaultId, 0, 10);
    }

    function testMoveCollateral() public {
        console.log("can stir collateral");
        cauldron.build(address(this), otherVaultId, baseId, usdcId);
        vm.expectEmit(true, true, false, true);
        emit VaultStirred(vaultId, otherVaultId, INK.u128(), 0);
        cauldron.stir(vaultId, otherVaultId, INK.u128(), 0);

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK.u128());
        assertEq(art, 0);
    }

    function testMoveDebt() public {
        console.log("can stir debt");
        cauldron.pour(vaultId, 0, ART.i128());
        cauldron.build(address(this), otherVaultId, baseId, daiId);
        cauldron.pour(otherVaultId, INK.i128(), 0);
        vm.expectEmit(true, true, false, true);
        emit VaultStirred(vaultId, otherVaultId, 0, ART.u128());
        cauldron.stir(vaultId, otherVaultId, 0, ART.u128());

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK.u128());
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK.u128());
        assertEq(art, ART.u128());
    }

    function testUndercollateralizedAtOrigin() public {
        console.log("cannot stir from vault with undercollateralized origin");
        cauldron.pour(vaultId, 0, ART.i128());
        cauldron.build(address(this), otherVaultId, baseId, usdcId);
        vm.expectRevert("Undercollateralized at origin");
        cauldron.stir(vaultId, otherVaultId, INK.u128(), 0);
    }
}

contract CauldronSlurpTests is BorrowedState {
    function testSlurp() public {
        console.log("can slurp");
        cauldron.slurp(vaultId, INK.u128(), ART.u128());
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);
    }
}