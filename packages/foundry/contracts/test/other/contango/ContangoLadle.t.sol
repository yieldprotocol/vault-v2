// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "../../utils/TestConstants.sol";
import "../../utils/Mocks.sol";

import "../../../other/contango/ContangoLadle.sol";

contract ContangoLadleTest is Test, TestConstants {
    using Mocks for *;

    ICauldron internal cauldron;

    ContangoLadle internal ladle;

    function setUp() public virtual {
        cauldron = ICauldron(Mocks.mock("Cauldron"));

        ladle = new ContangoLadle(cauldron, IWETH9(address(0xf00)));
    }

    function testRegularBuildDisabled() public {
        vm.expectRevert("Use deterministicBuild");
        ladle.build("series", "ilk", 0);
    }

    function testDeterministicBuildPermissions() public {
        vm.expectRevert("Access denied");
        ladle.deterministicBuild("vaultId", "series", "ilk");
    }

    function testDeterministicBuild() public {
        address bob = address(0xb0b);
        DataTypes.Vault memory vault = DataTypes.Vault({
            owner: bob,
            seriesId: "series",
            ilkId: "ilk"
        });

        ladle.grantRole(ContangoLadle.deterministicBuild.selector, bob);

        cauldron.build.mock(bob, "vaultId", "series", "ilk", vault);
        cauldron.build.verify(bob, "vaultId", "series", "ilk");

        vm.prank(bob);
        DataTypes.Vault memory vault_ = ladle.deterministicBuild(
            "vaultId",
            "series",
            "ilk"
        );

        assertEq0(abi.encode(vault_), abi.encode(vault));
    }
}
