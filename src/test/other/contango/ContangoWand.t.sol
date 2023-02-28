// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../../utils/TestConstants.sol";
import "../../utils/Mocks.sol";

import "../../../Cauldron.sol";
import "../../../other/contango/ContangoLadle.sol";
import "../../../other/contango/ContangoWand.sol";

contract ContangoWandTest is Test, TestConstants {
    ICauldron internal contangoCauldron =
        ICauldron(0x44386ddB4C44E7CB8981f97AF89E928Ddd4258DD);
    ICauldron internal yieldCauldron =
        ICauldron(0x23cc87FBEBDD67ccE167Fa9Ec6Ad3b7fE3892E30);

    ILadleGov public immutable contangoLadle =
        ILadleGov(0x93343C08e2055b7793a3336d659Be348FC1B08f9);
    ILadle public immutable yieldLadle =
        ILadle(0x16E25cf364CeCC305590128335B8f327975d0560);

    YieldSpaceMultiOracle public immutable yieldSpaceOracle =
        YieldSpaceMultiOracle(0xb958bA862D70C0a4bD0ea976f9a1907686dd41e2);
    CompositeMultiOracle public immutable compositeOracle =
        CompositeMultiOracle(0x750B3a18115fe090Bc621F9E4B90bd442bcd02F2);

    ContangoWand internal wand;

    bytes6 internal immutable baseId = USDC;
    bytes6 internal immutable seriesId = FYUSDC2206;
    bytes6 internal immutable ilkId = FYETH2206;

    function setUp() public virtual {
        vm.createSelectFork("ARBITRUM", 65404751);

        wand = new ContangoWand(
            ICauldronGov(address(contangoCauldron)),
            yieldCauldron,
            ILadleGov(address(contangoLadle)),
            yieldLadle,
            yieldSpaceOracle,
            compositeOracle
        );

        vm.startPrank(addresses[ARBITRUM][TIMELOCK]);
        AccessControl(address(contangoCauldron)).grantRole(
            Cauldron.setSpotOracle.selector,
            address(wand)
        );

        AccessControl(address(contangoCauldron)).grantRole(
            Cauldron.setLendingOracle.selector,
            address(wand)
        );
        vm.stopPrank();
    }

    function testCopySpotOracle_Auth() public {
        vm.expectRevert("Access denied");
        wand.copySpotOracle(baseId, ilkId);
    }

    function testCopySpotOracle() public {
        wand.grantRole(wand.copySpotOracle.selector, address(this));
        wand.copySpotOracle(baseId, ETH);

        DataTypes.SpotOracle memory yieldOracle = yieldCauldron.spotOracles(
            baseId,
            ETH
        );
        DataTypes.SpotOracle memory contangoOracle = contangoCauldron
            .spotOracles(baseId, ETH);

        assertEq(
            address(yieldOracle.oracle),
            address(contangoOracle.oracle),
            "oracle"
        );
        assertEq(yieldOracle.ratio, contangoOracle.ratio, "ratio");
    }

    function testCopyLendingOracle_Auth() public {
        vm.expectRevert("Access denied");
        wand.copyLendingOracle(baseId);
    }

    function testCopyLendingOracle() public {
        wand.grantRole(wand.copyLendingOracle.selector, address(this));
        wand.copyLendingOracle(baseId);

        IOracle yieldOracle = yieldCauldron.lendingOracles(baseId);
        IOracle contangoOracle = contangoCauldron.lendingOracles(baseId);

        assertEq(address(yieldOracle), address(contangoOracle), "oracle");
    }
}
