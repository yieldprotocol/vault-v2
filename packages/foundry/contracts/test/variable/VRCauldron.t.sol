// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Vm.sol";

import "./Fixture.sol";
import "../../variable/VYToken.sol";

abstract contract ZeroState is Fixture {
    ERC20Mock public ilk;
    bytes6 public ilkId;
    VYToken public vyToken;

    function setUp() public virtual override {
        super.setUp();
        vyToken = new VYToken(
            usdcId,
            IOracle(address(spotOracle)),
            IJoin(address(usdcJoin)),
            "",
            ""
        );
    }
}

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
        cauldron.setRateOracle(usdcId, IOracle(address(spotOracle)));
        cauldron.addBase(usdcId);
        assertEq(cauldron.bases(usdcId), true);
    }
}

contract AssetAndIlkAddedTests is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        cauldron.addAsset(usdcId, address(usdc));
    }

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

contract IlkAddition is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        cauldron.addAsset(usdcId, address(usdc));
        cauldron.setRateOracle(usdcId, IOracle(address(spotOracle)));

        ilkIds = new bytes6[](1);
        ilkIds[0] = usdcId;
    }

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
        cauldron.setRateOracle(otherIlkId, IOracle(address(spotOracle)));
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

contract VaultTest is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        cauldron.addAsset(usdcId, address(usdc));
        cauldron.setRateOracle(usdcId, IOracle(address(spotOracle)));

        ilkIds = new bytes6[](1);
        ilkIds[0] = usdcId;
    }

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

    function testVaultBuild() public {
        cauldron.setSpotOracle(baseId, usdcId, spotOracle, 1000000);
        cauldron.addIlks(baseId, ilkIds);

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

contract CauldronTestOnBuiltVault is ZeroState {
    function setUp() public virtual override {
        super.setUp();

        ilkIds = new bytes6[](1);
        ilkIds[0] = usdcId;

        cauldron.addAsset(usdcId, address(usdc));
        cauldron.setRateOracle(usdcId, IOracle(address(spotOracle)));
        cauldron.setSpotOracle(baseId, usdcId, spotOracle, 1000000);
        cauldron.addIlks(baseId, ilkIds);
        cauldron.build(address(this), vaultId, baseId, usdcId);
    }

    function testVaultBuildingWithSameIdFails() public {
        vm.expectRevert("Vault already exists");
        cauldron.build(address(this), vaultId, baseId, usdcId);
    }

    function testVaultDestroy() public {
        cauldron.destroy(vaultId);
        (address owner_, , ) = cauldron.vaults(vaultId);
        assertEq(owner_, address(0));
    }
}
