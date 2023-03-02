// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../../utils/TestConstants.sol";
import "../../utils/Mocks.sol";

import "../../../interfaces/IWitch.sol";
import "../../../Cauldron.sol";
import "../../../Join.sol";
import "../../../other/contango/ContangoLadle.sol";
import "../../../other/contango/ContangoWand.sol";

contract ContangoWandTest is Test, TestConstants {
    ICauldron internal contangoCauldron = ICauldron(0x44386ddB4C44E7CB8981f97AF89E928Ddd4258DD);
    ILadle public immutable contangoLadle = ILadle(0x93343C08e2055b7793a3336d659Be348FC1B08f9);
    IWitch internal immutable contangoWitch = IWitch(0x89343a24a217172A569A0bD68763Bf0671A3efd8);

    ICauldron internal yieldCauldron = ICauldron(0x23cc87FBEBDD67ccE167Fa9Ec6Ad3b7fE3892E30);
    ILadle public immutable yieldLadle = ILadle(0x16E25cf364CeCC305590128335B8f327975d0560);
    address internal immutable yieldTimelock = 0xd0a22827Aed2eF5198EbEc0093EA33A4CD641b6c;

    YieldSpaceMultiOracle public immutable yieldSpaceOracle =
        YieldSpaceMultiOracle(0xb958bA862D70C0a4bD0ea976f9a1907686dd41e2);
    CompositeMultiOracle public immutable compositeOracle =
        CompositeMultiOracle(0x750B3a18115fe090Bc621F9E4B90bd442bcd02F2);

    address internal bob = address(0xb0b);

    ContangoWand internal wand;

    function setUp() public virtual {
        vm.createSelectFork("ARBITRUM", 65404751);

        wand = new ContangoWand(
            contangoCauldron,
            yieldCauldron,
            contangoLadle,
            yieldLadle,
            yieldSpaceOracle,
            compositeOracle,
            yieldTimelock,
            contangoWitch
        );

        bytes4 root = 0x0;
        wand.grantRole(root, addresses[ARBITRUM][TIMELOCK]);

        vm.startPrank(addresses[ARBITRUM][TIMELOCK]);

        AccessControl(address(yieldLadle.joins(USDT))).grantRole(root, address(wand));
        AccessControl(address(yieldCauldron.series(FYUSDT2306).fyToken)).grantRole(root, address(wand));

        wand.grantRole(wand.copySpotOracle.selector, address(this));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.setSpotOracle.selector, address(wand));
        wand.grantRole(wand.copyLendingOracle.selector, address(this));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.setLendingOracle.selector, address(wand));
        wand.grantRole(wand.copyDebtLimits.selector, address(this));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.setDebtLimits.selector, address(wand));
        wand.grantRole(wand.addAsset.selector, address(this));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.addAsset.selector, address(wand));
        wand.grantRole(wand.addSeries.selector, address(this));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.addSeries.selector, address(wand));
        wand.grantRole(wand.addIlks.selector, address(this));
        AccessControl(address(contangoCauldron)).grantRole(Cauldron.addIlks.selector, address(wand));
        wand.grantRole(wand.setRatio.selector, address(this));
        wand.grantRole(wand.boundRatio.selector, address(this));
        wand.grantRole(wand.setDebtLimits.selector, address(this));
        wand.grantRole(wand.setDefaultDebtLimits.selector, address(this));
        wand.grantRole(wand.boundDebtLimits.selector, address(this));
        AccessControl(address(yieldSpaceOracle)).grantRole(YieldSpaceMultiOracle.setSource.selector, address(wand));
        wand.grantRole(wand.setYieldSpaceOracleSource.selector, address(this));
        AccessControl(address(compositeOracle)).grantRole(CompositeMultiOracle.setSource.selector, address(wand));
        wand.grantRole(wand.setCompositeOracleSource.selector, address(this));
        AccessControl(address(compositeOracle)).grantRole(CompositeMultiOracle.setPath.selector, address(wand));
        wand.grantRole(wand.setCompositeOraclePath.selector, address(this));
        AccessControl(address(contangoLadle)).grantRole(ILadle.addPool.selector, address(wand));
        wand.grantRole(wand.addPool.selector, address(this));
        AccessControl(address(contangoLadle)).grantRole(ILadle.addIntegration.selector, address(wand));
        wand.grantRole(wand.addIntegration.selector, address(this));
        AccessControl(address(contangoLadle)).grantRole(ILadle.addToken.selector, address(wand));
        wand.grantRole(wand.addToken.selector, address(this));
        AccessControl(address(contangoLadle)).grantRole(ILadle.addJoin.selector, address(wand));
        wand.grantRole(wand.addJoin.selector, address(this));
        vm.stopPrank();
    }

    function testCopySpotOracle_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.copySpotOracle(USDC, FYETH2306);
    }

    function testCopySpotOracle() public {
        wand.copySpotOracle(USDC, ETH);

        DataTypes.SpotOracle memory yieldOracle = yieldCauldron.spotOracles(USDC, ETH);
        DataTypes.SpotOracle memory contangoOracle = contangoCauldron.spotOracles(USDC, ETH);

        assertEq(address(yieldOracle.oracle), address(contangoOracle.oracle), "oracle");
        assertEq(yieldOracle.ratio, contangoOracle.ratio, "ratio");
    }

    function testCopyLendingOracle_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.copyLendingOracle(USDC);
    }

    function testCopyLendingOracle() public {
        wand.copyLendingOracle(USDC);

        IOracle yieldOracle = yieldCauldron.lendingOracles(USDC);
        IOracle contangoOracle = contangoCauldron.lendingOracles(USDC);

        assertEq(address(yieldOracle), address(contangoOracle), "oracle");
    }

    function testCopyDebtLimits_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.copyDebtLimits(USDC, FYETH2306);
    }

    function testCopyDebtLimits() public {
        wand.copyDebtLimits(USDC, ETH);

        DataTypes.Debt memory yieldDebt = yieldCauldron.debt(USDC, ETH);
        DataTypes.Debt memory contangoDebt = contangoCauldron.debt(USDC, ETH);

        assertEq(yieldDebt.max, contangoDebt.max, "max");
        assertEq(yieldDebt.min, contangoDebt.min, "min");
        assertEq(yieldDebt.dec, contangoDebt.dec, "dec");
    }

    function testCopyDebtLimits_FromSeries() public {
        wand.copyDebtLimits(USDC, FYETH2306);

        DataTypes.Debt memory yieldDebt = yieldCauldron.debt(USDC, ETH);
        DataTypes.Debt memory contangoDebt = contangoCauldron.debt(USDC, FYETH2306);

        assertEq(yieldDebt.max, contangoDebt.max, "max");
        assertEq(yieldDebt.min, contangoDebt.min, "min");
        assertEq(yieldDebt.dec, contangoDebt.dec, "dec");
    }

    function testAddAsset_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.addAsset(USDT);
    }

    function testAddAsset() public {
        wand.addAsset(USDT);
        assertEq(contangoCauldron.assets(USDT), 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, "asset");
    }

    function testAddAsset_FromSeries() public {
        wand.addAsset(FYUSDT2306);
        assertEq(contangoCauldron.assets(FYUSDT2306), 0x035072cb2912DAaB7B578F468Bd6F0d32a269E32, "asset");
    }

    function testAddSeries_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.addSeries(FYUSDT2306);
    }

    function testAddSeries() public {
        wand.addSeries(FYUSDT2306);

        DataTypes.Series memory yieldSeries = yieldCauldron.series(FYUSDT2306);
        DataTypes.Series memory contangoSeries = contangoCauldron.series(FYUSDT2306);

        assertEq(address(yieldSeries.fyToken), address(contangoSeries.fyToken), "fyToken");
        assertEq(yieldSeries.baseId, contangoSeries.baseId, "baseId");
        assertEq(yieldSeries.maturity, contangoSeries.maturity, "maturity");
    }

    function testSetRatio_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.setRatio(USDT, FYETH2306, 1.4e6);
    }

    function testSetRatio_BoundsSetForSeriesId() public {
        wand.addAsset(USDT);
        uint32 bound = 1.3e6;
        wand.boundRatio(USDT, FYETH2306, bound);

        vm.expectRevert("Ratio out of bounds");
        wand.setRatio(USDT, FYETH2306, bound - 1);

        wand.setRatio(USDT, FYETH2306, bound);
        DataTypes.SpotOracle memory contangoOracle = contangoCauldron.spotOracles(USDT, FYETH2306);
        assertEq(address(contangoOracle.oracle), address(compositeOracle), "oracle");
        assertEq(contangoOracle.ratio, bound, "ratio");
    }

    function testSetRatio_BoundsSetForSeriesIdBaseId() public {
        wand.addAsset(USDT);
        uint32 bound = 1.3e6;
        wand.boundRatio(USDT, ETH, bound);

        vm.expectRevert("Ratio out of bounds");
        wand.setRatio(USDT, FYETH2306, bound - 1);

        wand.setRatio(USDT, FYETH2306, bound);
        DataTypes.SpotOracle memory contangoOracle = contangoCauldron.spotOracles(USDT, FYETH2306);
        assertEq(address(contangoOracle.oracle), address(compositeOracle), "oracle");
        assertEq(contangoOracle.ratio, bound, "ratio");
    }

    function testSetRatio_YieldCauldronAsBounds_BoundsSetForAssetId() public {
        wand.addAsset(USDT);
        uint32 bound = 1.4e6;

        vm.expectRevert("Ratio out of bounds");
        wand.setRatio(USDT, ETH, bound - 1);

        wand.setRatio(USDT, ETH, bound);
        DataTypes.SpotOracle memory contangoOracle = contangoCauldron.spotOracles(USDT, ETH);
        assertEq(address(contangoOracle.oracle), address(compositeOracle), "oracle");
        assertEq(contangoOracle.ratio, bound, "ratio");
    }

    function testSetRatio_YieldCauldronAsBounds_BoundsSetForSeriesIdBaseId() public {
        wand.addAsset(USDT);
        uint32 bound = 1.4e6;

        vm.expectRevert("Ratio out of bounds");
        wand.setRatio(USDT, FYETH2306, bound - 1);

        wand.setRatio(USDT, FYETH2306, bound);
        DataTypes.SpotOracle memory contangoOracle = contangoCauldron.spotOracles(USDT, FYETH2306);
        assertEq(address(contangoOracle.oracle), address(compositeOracle), "oracle");
        assertEq(contangoOracle.ratio, bound, "ratio");
    }

    function testAddIlks_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.addSeries(FYUSDT2306);
    }

    function testAddIlks() public {
        wand.addAsset(USDT);
        wand.copyLendingOracle(USDT);
        wand.addSeries(FYUSDT2306);
        wand.setRatio(USDT, FYETH2306, 1.4e6);

        bytes6[] memory ilkIds = new bytes6[](1);
        ilkIds[0] = FYETH2306;

        wand.addIlks(FYUSDT2306, ilkIds);

        assertTrue(contangoCauldron.ilks(FYUSDT2306, FYETH2306), "ilk");
    }

    function testSetDebtLimits_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.setDebtLimits(USDT, FYETH2306, 500_000, 40);
    }

    function testSetDebtLimits_NoDefaultDebtLimits() public {
        vm.expectRevert("Default debt limits not set");
        wand.setDebtLimits(USDT, FYETH2306, 500_000, 40);
    }

    function testSetDebtLimits() public {
        wand.addAsset(USDT);
        wand.setDefaultDebtLimits(500_000, 40);

        wand.setDebtLimits(USDT, FYETH2306, 500_000, 40);

        DataTypes.Debt memory contangoDebtLimits = contangoCauldron.debt(USDT, FYETH2306);

        assertEq(contangoDebtLimits.max, 500_000, "max");
        assertEq(contangoDebtLimits.min, 40, "min");
        assertEq(contangoDebtLimits.dec, 6, "dec");
    }

    function testSetDebtLimits_OutsideDefaultLimits() public {
        wand.addAsset(USDT);

        wand.setDefaultDebtLimits(500_000, 40);

        vm.expectRevert("Max debt out of bounds");
        wand.setDebtLimits(USDT, FYETH2306, 500_000 + 1, 40);

        vm.expectRevert("Min debt out of bounds");
        wand.setDebtLimits(USDT, FYETH2306, 500_000, 40 - 1);
    }

    function testSetDebtLimits_OverrideLimitsForPair() public {
        wand.addAsset(USDT);
        wand.setDefaultDebtLimits(500_000, 40);

        wand.boundDebtLimits(USDT, FYETH2306, 1_000_000, 20);

        wand.setDebtLimits(USDT, FYETH2306, 1_000_000, 20);

        DataTypes.Debt memory contangoDebtLimits = contangoCauldron.debt(USDT, FYETH2306);

        assertEq(contangoDebtLimits.max, 1_000_000, "max");
        assertEq(contangoDebtLimits.min, 20, "min");
        assertEq(contangoDebtLimits.dec, 6, "dec");
    }

    function testSetYieldSpaceOracleSource_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.setYieldSpaceOracleSource(FYUSDT2306);
    }

    function testSetYieldSpaceOracleSource() public {
        wand.setYieldSpaceOracleSource(FYUSDT2306);

        (IPool pool, bool lending) = yieldSpaceOracle.sources(USDT, FYUSDT2306);
        assertEq(address(pool), 0xc6078e090641cC32b05a7F3F102F272A4Ee19867, "pool");
        assertTrue(lending, "lending");

        (pool, lending) = yieldSpaceOracle.sources(FYUSDT2306, USDT);
        assertEq(address(pool), 0xc6078e090641cC32b05a7F3F102F272A4Ee19867, "pool");
        assertFalse(lending, "lending");
    }

    function testSetYieldSpaceOracleSource_InvalidSeries() public {
        vm.expectRevert("Pool not known to the Yield Ladle");
        wand.setYieldSpaceOracleSource("series");
    }

    function testCompositeOracleSource_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.setCompositeOracleSource(USDT, FYETH2306);
    }

    function testCompositeOracleSource_InvalidPair() public {
        vm.expectRevert("YieldSpace oracle not set");
        wand.setCompositeOracleSource(USDT, FYETH2306);
    }

    function testCompositeOracleSource_FYToken() public {
        wand.setYieldSpaceOracleSource(FYUSDT2306);

        wand.setCompositeOracleSource(USDT, FYUSDT2306);

        IOracle source = compositeOracle.sources(USDT, FYUSDT2306);
        assertEq(address(source), address(yieldSpaceOracle), "source");
    }

    function testCompositeOracleSource_Asset() public {
        wand.setCompositeOracleSource(USDT, ETH);

        IOracle source = compositeOracle.sources(USDT, ETH);
        assertEq(address(source), 0x8E9696345632796e7D80fB341fF4a2A60aa39C89, "source");
    }

    function testCompositeOraclePath_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.setCompositeOraclePath(USDT, FYETH2306, new bytes6[](0));
    }

    // function testCompositeOraclePath_InvalidPair() public {
    //     vm.expectRevert("Path already set");
    //     wand.setCompositeOraclePath(USDC, FYETH2306, new bytes6[](0));
    // }

    function testCompositeOraclePath() public {
        wand.setYieldSpaceOracleSource(FYUSDT2306);
        wand.setCompositeOracleSource(USDT, ETH);
        wand.setCompositeOracleSource(USDT, FYUSDT2306);

        bytes6[] memory path = new bytes6[](1);
        path[0] = ETH;

        wand.setCompositeOraclePath(USDT, FYETH2306, path);

        (uint256 amountQuote, uint256 updateTime) = compositeOracle.peek(USDT, FYETH2306, 1000e6);
        assertGt(amountQuote, 0, "amountQuote");
        assertGt(updateTime, 0, "updateTime");
    }

    function testAddPool_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.addPool(FYUSDT2306);
    }

    function testAddPool_Invalid() public {
        vm.expectRevert("Pool not known to the Yield Ladle");
        wand.addPool("meh");
    }

    function testAddPool() public {
        wand.addAsset(USDT);
        wand.copyLendingOracle(USDT);
        wand.addSeries(FYUSDT2306);

        wand.addPool(FYUSDT2306);

        assertEq(contangoLadle.pools(FYUSDT2306), 0xc6078e090641cC32b05a7F3F102F272A4Ee19867, "pool");
    }

    function testIntegration_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.addIntegration(address(0));
    }

    function testAddIntegration() public {
        assertTrue(yieldLadle.integrations(0xE779cd75E6c574d83D3FD6C92F3CBE31DD32B1E1), "yield integration");

        wand.addIntegration(0xE779cd75E6c574d83D3FD6C92F3CBE31DD32B1E1);

        assertTrue(contangoLadle.integrations(0xE779cd75E6c574d83D3FD6C92F3CBE31DD32B1E1), "yield integration");
    }

    function testToken_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.addToken(address(0));
    }

    function testAddToken() public {
        assertTrue(yieldLadle.tokens(0xad1983745D6c739537fEaB5bed45795f47A940b3), "yield integration");

        wand.addToken(0xad1983745D6c739537fEaB5bed45795f47A940b3);

        assertTrue(contangoLadle.tokens(0xad1983745D6c739537fEaB5bed45795f47A940b3), "yield integration");
    }

    function testAddJoin_Auth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        wand.addJoin(FYUSDT2306, IJoin(address(0)));
    }

    function testAddJoin() public {
        wand.addAsset(USDT);

        IJoin join = yieldLadle.joins(USDT);

        wand.addJoin(USDT, join);

        assertEq(address(contangoLadle.joins(USDT)), address(join), "pool");
    }
}
