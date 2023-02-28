// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../../utils/TestConstants.sol";
import "../../utils/Mocks.sol";

import "../../../Cauldron.sol";
import "../../../other/contango/ContangoLadle.sol";
import "../../../other/contango/ContangoWand.sol";

contract ContangoWandTest is Test, TestConstants {
    ICauldron internal contangoCauldron = ICauldron(0x44386ddB4C44E7CB8981f97AF89E928Ddd4258DD);
    ICauldron internal yieldCauldron = ICauldron(0x23cc87FBEBDD67ccE167Fa9Ec6Ad3b7fE3892E30);

    ILadleGov public immutable contangoLadle = ILadleGov(0x93343C08e2055b7793a3336d659Be348FC1B08f9);
    ILadle public immutable yieldLadle = ILadle(0x16E25cf364CeCC305590128335B8f327975d0560);

    YieldSpaceMultiOracle public immutable yieldSpaceOracle =
        YieldSpaceMultiOracle(0xb958bA862D70C0a4bD0ea976f9a1907686dd41e2);
    CompositeMultiOracle public immutable compositeOracle =
        CompositeMultiOracle(0x750B3a18115fe090Bc621F9E4B90bd442bcd02F2);

    ContangoWand internal wand;

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
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.setSpotOracle.selector, address(wand));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.setLendingOracle.selector, address(wand));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.setDebtLimits.selector, address(wand));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.addAsset.selector, address(wand));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.addSeries.selector, address(wand));
        vm.stopPrank();
    }

    function testCopySpotOracle_Auth() public {
        vm.expectRevert("Access denied");
        wand.copySpotOracle(USDC, FYETH2306);
    }

    function testCopySpotOracle() public {
        wand.grantRole(wand.copySpotOracle.selector, address(this));
        wand.copySpotOracle(USDC, ETH);

        DataTypes.SpotOracle memory yieldOracle = yieldCauldron.spotOracles(USDC, ETH);
        DataTypes.SpotOracle memory contangoOracle = contangoCauldron.spotOracles(USDC, ETH);

        assertEq(address(yieldOracle.oracle), address(contangoOracle.oracle), "oracle");
        assertEq(yieldOracle.ratio, contangoOracle.ratio, "ratio");
    }

    function testCopyLendingOracle_Auth() public {
        vm.expectRevert("Access denied");
        wand.copyLendingOracle(USDC);
    }

    function testCopyLendingOracle() public {
        wand.grantRole(wand.copyLendingOracle.selector, address(this));
        wand.copyLendingOracle(USDC);

        IOracle yieldOracle = yieldCauldron.lendingOracles(USDC);
        IOracle contangoOracle = contangoCauldron.lendingOracles(USDC);

        assertEq(address(yieldOracle), address(contangoOracle), "oracle");
    }

    function testCopyDebtLimits_Auth() public {
        vm.expectRevert("Access denied");
        wand.copyDebtLimits(USDC, FYETH2306);
    }

    function testCopyDebtLimits() public {
        wand.grantRole(wand.copyDebtLimits.selector, address(this));
        wand.copyDebtLimits(USDC, ETH);

        DataTypes.Debt memory yieldDebt = yieldCauldron.debt(USDC, ETH);
        DataTypes.Debt memory contangoDebt = contangoCauldron.debt(USDC, ETH);

        assertEq(yieldDebt.max, contangoDebt.max, "max");
        assertEq(yieldDebt.min, contangoDebt.min, "min");
        assertEq(yieldDebt.dec, contangoDebt.dec, "dec");
    }

    function testCopyDebtLimits_FromSeries() public {
        wand.grantRole(wand.copyDebtLimits.selector, address(this));
        wand.copyDebtLimits(USDC, FYETH2306);

        DataTypes.Debt memory yieldDebt = yieldCauldron.debt(USDC, ETH);
        DataTypes.Debt memory contangoDebt = contangoCauldron.debt(USDC, FYETH2306);

        assertEq(yieldDebt.max, contangoDebt.max, "max");
        assertEq(yieldDebt.min, contangoDebt.min, "min");
        assertEq(yieldDebt.dec, contangoDebt.dec, "dec");
    }

    function testAddAsset_Auth() public {
        vm.expectRevert("Access denied");
        wand.addAsset(USDT);
    }

    function testAddAsset() public {
        wand.grantRole(wand.addAsset.selector, address(this));
        wand.addAsset(USDT);
        assertEq(contangoCauldron.assets(USDT), 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, "asset");
    }

    function testAddAsset_FromSeries() public {
        wand.grantRole(wand.addAsset.selector, address(this));
        wand.addAsset(FYUSDT2306);
        assertEq(contangoCauldron.assets(FYUSDT2306), 0x035072cb2912DAaB7B578F468Bd6F0d32a269E32, "asset");
    }

    function testAddSeries_Auth() public {
        vm.expectRevert("Access denied");
        wand.addSeries(FYUSDT2306);
    }

    function testAddSeries() public {
        wand.grantRole(wand.addAsset.selector, address(this));
        wand.addAsset(USDT);
        wand.grantRole(wand.copyLendingOracle.selector, address(this));
        wand.copyLendingOracle(USDT);

        wand.grantRole(wand.addSeries.selector, address(this));
        wand.addSeries(FYUSDT2306);

        DataTypes.Series memory yieldSeries = yieldCauldron.series(FYUSDT2306);
        DataTypes.Series memory contangoSeries = contangoCauldron.series(FYUSDT2306);

        assertEq(address(yieldSeries.fyToken), address(contangoSeries.fyToken), "fyToken");
        assertEq(yieldSeries.baseId, contangoSeries.baseId, "baseId");
        assertEq(yieldSeries.maturity, contangoSeries.maturity, "maturity");
    }
}
