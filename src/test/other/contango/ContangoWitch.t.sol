// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";

import "../../utils/TestConstants.sol";
import "../../utils/Mocks.sol";

import "../../../interfaces/IWitch.sol";
import "../../../other/contango/ContangoWitch.sol";

import "./ContangoTestUtils.sol";

using ContangoTestUtils for ILadle;
using Math for uint256;
using Math for uint128;

abstract contract ContangoWitchStateZero is
    Test,
    TestConstants,
    IContangoWitchEvents
{
    using Mocks for *;

    event Auctioned(
        bytes12 indexed vaultId,
        DataTypes.Auction auction,
        uint256 duration,
        uint256 initialProportion
    );
    event Cancelled(bytes12 indexed vaultId);
    event Ended(bytes12 indexed vaultId);
    event Bought(
        bytes12 indexed vaultId,
        address indexed buyer,
        uint256 ink,
        uint256 art
    );
    event LineSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint32 duration,
        uint64 proportion,
        uint64 initialOffer
    );
    event LimitSet(bytes6 indexed ilkId, bytes6 indexed baseId, uint128 max);
    event Point(
        bytes32 indexed param,
        address indexed oldValue,
        address indexed newValue
    );
    event ProtectedSet(address indexed a, bool protected);
    event AuctioneerRewardSet(uint256 auctioneerReward);

    bytes12 internal constant VAULT_ID = "vault";
    bytes6 internal constant ILK_ID = ETH;
    bytes6 internal constant BASE_ID = USDC;
    bytes6 internal constant SERIES_ID = FYETH2206;
    uint32 internal constant AUCTION_DURATION = 1 hours;
    uint32 internal constant INSURANCE_AUCTION_DURATION = 2 hours;

    // address internal admin;
    address internal deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    address internal ada = address(0xada);
    address internal bot = address(0xb07);
    address internal bad = address(0xbad);
    address internal cool = address(0xc001);
    address internal insurancePremiumReceiver = address(0xfee);

    IContangoWitchListener public contango;
    IContangoInsuranceFund insuranceFund;
    ICauldron internal cauldron;
    ILadle internal ladle;

    ContangoWitch internal witch;
    IWitch internal iWitch;

    function setUp() public virtual {
        cauldron = ICauldron(Mocks.mock("Cauldron"));
        ladle = ILadle(Mocks.mock("Ladle"));
        contango = IContangoWitchListener(Mocks.mock("ContangoWitchListener"));
        insuranceFund = IContangoInsuranceFund(
            Mocks.mock("ContangoInsuranceFund")
        );

        vm.startPrank(ada);
        witch = new ContangoWitch(cauldron, ladle);
        witch.grantRole(Witch.point.selector, ada);
        witch.grantRole(Witch.setLineAndLimit.selector, ada);
        witch.grantRole(Witch.setProtected.selector, ada);
        witch.grantRole(Witch.setAuctioneerReward.selector, ada);
        witch.grantRole(ContangoWitch.setInsuranceLine.selector, ada);
        witch.grantRole(ContangoWitch.setInsuranceLineStatus.selector, ada);
        witch.grantRole(ContangoWitch.setDefaultInsurancePremium.selector, ada);
        vm.stopPrank();

        vm.label(ada, "Ada");
        vm.label(bot, "Bot");

        iWitch = IWitch(address(witch));
    }
}

contract ContangoWitchStateZeroTest is ContangoWitchStateZero {
    function testPointRequiresAuth() public {
        vm.prank(bad);
        vm.expectRevert("Access denied");
        witch.point("ladle", bad);
    }

    function testPointRequiresLadle() public {
        vm.prank(ada);
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.UnrecognisedParam.selector,
                bytes32("cauldron")
            )
        );
        witch.point("cauldron", bad);
    }

    function testPoint() public {
        vm.expectEmit(true, true, false, true);
        emit Point("ladle", address(ladle), cool);

        vm.prank(ada);
        witch.point("ladle", cool);

        assertEq(address(witch.ladle()), cool);
    }

    function testSetLineAndLimitRequiresAuth() public {
        vm.prank(bad);
        vm.expectRevert("Access denied");
        witch.setLineAndLimit("", "", 0, 0, 0, 0);
    }

    function testSetLineAndLimitRequiresCollateralProportionTooHigh() public {
        vm.prank(ada);
        vm.expectRevert("Collateral Proportion above 100%");
        witch.setLineAndLimit("", "", 0, 0, 1e18 + 1, 0);
    }

    function testSetLineAndLimitRequiresProportionTooHigh() public {
        vm.prank(ada);
        vm.expectRevert("Vault Proportion above 100%");
        witch.setLineAndLimit("", "", 0, 1e18 + 1, 0, 0);
    }

    function testSetLineAndLimitRequiresCollateralProportionTooLow() public {
        vm.prank(ada);
        vm.expectRevert("Collateral Proportion below 1%");
        witch.setLineAndLimit("", "", 0, 0, 0.01e18 - 1, 0);
    }

    function testSetLineAndLimitRequiresProportionTooLow() public {
        vm.prank(ada);
        vm.expectRevert("Vault Proportion below 1%");
        witch.setLineAndLimit("", "", 0, 0.01e18 - 1, 1e18, 0);
    }

    function testSetLineAndLimit() public {
        uint64 proportion = 0.5e18;
        uint64 initialOffer = 0.75e18;
        uint128 max = 100_000_000e18;

        vm.expectEmit(true, true, false, true);
        emit LineSet(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer
        );

        vm.expectEmit(true, true, false, true);
        emit LimitSet(ILK_ID, BASE_ID, max);

        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer,
            max
        );

        (uint32 _duration, uint64 _proportion, uint64 _initialOffer) = witch
            .lines(ILK_ID, BASE_ID);

        assertEq(_duration, AUCTION_DURATION);
        assertEq(_proportion, proportion);
        assertEq(_initialOffer, initialOffer);

        (uint128 _max, uint128 _sum) = witch.limits(ILK_ID, BASE_ID);

        assertEq(_max, max);
        assertEq(_sum, 0);
    }

    function testSetDefaultInsurancePremiumRequiresAuth() public {
        vm.prank(bad);
        vm.expectRevert("Access denied");
        witch.setDefaultInsurancePremium(0);
    }

    function testSetDefaultInsurancePremiumRequiresTooHigh() public {
        vm.prank(ada);
        vm.expectRevert("Default Insurance Premium above 100%");
        witch.setDefaultInsurancePremium(1e18 + 1);
    }

    function testSetDefaultInsurancePremium() public {
        uint64 defaultInsurancePremium = 0.01e18;

        vm.expectEmit(true, true, true, true);
        emit DefaultInsurancePremiumSet(defaultInsurancePremium);

        vm.prank(ada);
        witch.setDefaultInsurancePremium(defaultInsurancePremium);
    }

    function testSetInsuranceLineRequiresAuth() public {
        vm.prank(bad);
        vm.expectRevert("Access denied");
        witch.setInsuranceLine({
            ilkId: "",
            baseId: "",
            duration: 0,
            maxInsuredProportion: 0,
            insuranceFund: IContangoInsuranceFund(address(0)),
            insurancePremium: 0,
            insurancePremiumReceiver: address(0)
        });
    }

    function testSetInsuranceLineRequiresMaxInsuredProportionTooHigh() public {
        vm.prank(ada);
        vm.expectRevert("Max Insured Proportion above 100%");
        witch.setInsuranceLine({
            ilkId: "",
            baseId: "",
            duration: 0,
            maxInsuredProportion: 1e18 + 1,
            insuranceFund: IContangoInsuranceFund(address(0)),
            insurancePremium: 0,
            insurancePremiumReceiver: address(0)
        });
    }

    function testSetInsuranceLineRequiresInsurancePremiumProportionTooHigh()
        public
    {
        vm.prank(ada);
        vm.expectRevert("Insurance Premium above 100%");
        witch.setInsuranceLine({
            ilkId: "",
            baseId: "",
            duration: 0,
            maxInsuredProportion: 0,
            insuranceFund: IContangoInsuranceFund(address(0)),
            insurancePremium: 1e18 + 1,
            insurancePremiumReceiver: address(0)
        });
    }

    function testSetInsuranceLine() public {
        uint64 maxInsuredProportion = 0.1e18;
        uint64 insurancePremium = 0.01e18;

        vm.expectEmit(true, true, true, true);
        emit InsuranceLineSet(
            ILK_ID,
            BASE_ID,
            INSURANCE_AUCTION_DURATION,
            maxInsuredProportion,
            insuranceFund,
            insurancePremium,
            insurancePremiumReceiver
        );

        vm.prank(ada);
        witch.setInsuranceLine(
            ILK_ID,
            BASE_ID,
            INSURANCE_AUCTION_DURATION,
            maxInsuredProportion,
            insuranceFund,
            insurancePremium,
            insurancePremiumReceiver
        );
    }

    function testSetInsuranceLineStatusRequiresAuth() public {
        vm.prank(bad);
        vm.expectRevert("Access denied");
        witch.setInsuranceLineStatus("", "", true);
    }

    function testSetInsuranceLineStatus() public {
        vm.expectEmit(true, true, true, true);
        emit InsuranceLineStatusSet(ILK_ID, BASE_ID, true);

        vm.prank(ada);
        witch.setInsuranceLineStatus(ILK_ID, BASE_ID, true);
    }

    function testSetProtectedRequiresAuth() public {
        vm.prank(bad);
        vm.expectRevert("Access denied");
        witch.setProtected(address(0), true);
    }

    function testSetProtected() public {
        address protected = Mocks.mock("protected");

        vm.expectEmit(true, true, false, true);
        emit ProtectedSet(protected, true);

        vm.prank(ada);
        witch.setProtected(protected, true);

        assertTrue(witch.protected(protected));
    }

    function testSetAuctioneerRewardRequiresAuth() public {
        vm.prank(bad);
        vm.expectRevert("Access denied");
        witch.setAuctioneerReward(0);
    }

    function testSetAuctioneerRewardTooHigh() public {
        vm.prank(ada);
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.AuctioneerRewardTooHigh.selector,
                1e18,
                1.00001e18
            )
        );
        witch.setAuctioneerReward(1.00001e18);
    }

    function testSetAuctioneerReward() public {
        vm.expectEmit(true, true, false, true);
        emit AuctioneerRewardSet(0.02e18);

        vm.prank(ada);
        witch.setAuctioneerReward(0.02e18);

        assertEq(witch.auctioneerReward(), 0.02e18);
    }
}

abstract contract ContangoWitchWithMetadata is ContangoWitchStateZero {
    using Mocks for *;

    DataTypes.Vault vault;
    DataTypes.Series series;
    DataTypes.Balances balances;
    DataTypes.Debt debt;

    uint96 max = 100 ether;
    uint24 dust = 5000;
    uint8 dec = 6;

    uint64 proportion = 0.5e18;
    uint64 initialOffer = 0.714e18;

    function setUp() public virtual override {
        super.setUp();

        vault = DataTypes.Vault({
            owner: address(contango),
            seriesId: SERIES_ID,
            ilkId: ILK_ID
        });

        series = DataTypes.Series({
            fyToken: IFYToken(Mocks.mock("FYToken")),
            baseId: BASE_ID,
            maturity: uint32(block.timestamp + 30 days)
        });

        balances = DataTypes.Balances({art: 100_000e6, ink: 100 ether});

        debt = DataTypes.Debt({
            max: 0, // Not used by the Witch
            min: dust, // Witch uses the cauldron min debt as dust
            dec: dec,
            sum: 0 // Not used by the Witch
        });

        cauldron.vaults.mock(VAULT_ID, vault);
        cauldron.series.mock(SERIES_ID, series);
        cauldron.balances.mock(VAULT_ID, balances);
        cauldron.debt.mock(BASE_ID, ILK_ID, debt);

        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer,
            max
        );
    }

    function _verifyAuctionStarted(bytes12 vaultId) internal {
        contango.auctionStarted.mockAndVerify(vaultId);
    }

    function _verifyCollateralBought(
        bytes12 vaultId,
        address buyer,
        uint256 ink,
        uint256 art
    ) internal {
        contango.collateralBought.mockAndVerify(vaultId, buyer, ink, art);
    }

    function _verifyAuctionEnded(bytes12 vaultId, address owner) internal {
        contango.auctionEnded.mockAndVerify(vaultId, owner);
    }
}

contract ContangoWitchWithMetadataTest is ContangoWitchWithMetadata {
    using Mocks for *;

    function testCalcPayout() public {
        // 100 * 0.5 * 0.714 = 35.7
        // (ink * proportion * initialOffer)
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .calcPayout(VAULT_ID, bot, 50_000e6);
        assertEq(liquidatorCut, 35.7 ether);
        // on a non-started auction it's always assumed that liquidator == auctioneer
        assertEq(auctioneerCut, 0);
        assertEq(artIn, 50_000e6);

        skip(5 minutes);
        // Nothing changes as auction was never started
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            50_000e6
        );
        assertEq(liquidatorCut, 35.7 ether);
        assertEq(auctioneerCut, 0);
        assertEq(artIn, 50_000e6);
    }

    function testCalcPayoutEdgeCases() public {
        (uint256 liquidatorCut, , uint256 artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            0
        );
        assertEq(liquidatorCut, 0);
        assertEq(artIn, 0);

        (liquidatorCut, , artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            type(uint256).max
        );
        assertEq(liquidatorCut, 35.7 ether);
        assertEq(artIn, 50_000e6);
    }

    function testCalcPayoutFuzzArtIn(uint256 maxArtIn) public {
        (uint256 liquidatorCut, , uint256 artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            maxArtIn
        );

        assertLe(liquidatorCut, 35.7 ether);
        assertGe(liquidatorCut, 0);

        assertGe(artIn, 0);
        assertLe(artIn, 50_000e6);
    }

    function testCalcPayoutFuzzCollateralProportion(uint64 io) public {
        vm.assume(io <= 1e18 && io >= 0.01e18);

        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            io,
            max
        );

        (uint256 liquidatorCut, , ) = witch.calcPayout(VAULT_ID, bot, 50_000e6);

        assertLe(liquidatorCut, 50 ether);
        assertGe(liquidatorCut, 0.5 ether);
    }

    function testCalcPayoutFuzzElapsed(uint16 elapsed) public {
        skip(elapsed);

        (uint256 liquidatorCut, , ) = witch.calcPayout(VAULT_ID, bot, 50_000e6);

        assertLe(liquidatorCut, 50 ether);
    }

    function testWitchIsTooOld() public {
        vm.warp(uint256(type(uint32).max) + 1);
        vm.expectRevert(Witch.WitchIsDead.selector);
        witch.auction(VAULT_ID, bot);
    }

    function testVaultNotUndercollateralised() public {
        cauldron.level.mock(VAULT_ID, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.NotUnderCollateralised.selector,
                VAULT_ID
            )
        );
        witch.auction(VAULT_ID, bot);
    }

    function testVaultIsProtected() public {
        // Given
        address owner = Mocks.mock("owner");
        vm.prank(ada);
        witch.setProtected(owner, true);

        // protected owner
        vault.owner = owner;
        cauldron.vaults.mock(VAULT_ID, vault);

        // When
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.VaultAlreadyUnderAuction.selector,
                VAULT_ID,
                owner
            )
        );
        witch.auction(VAULT_ID, bot);
    }

    function testAuctionAVaultWithoutLimitsSet() public {
        // Given
        witch = new ContangoWitch(cauldron, ladle);

        // When
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.VaultNotLiquidatable.selector,
                ILK_ID,
                BASE_ID
            )
        );
        witch.auction(VAULT_ID, bot);
    }

    function testCanAuctionVault() public {
        cauldron.level.mockAndVerify(VAULT_ID, -1);
        cauldron.give.mockAndVerify(VAULT_ID, address(witch), vault);

        _verifyAuctionStarted(VAULT_ID);

        vm.expectEmit(true, true, true, true);
        emit Auctioned(
            VAULT_ID,
            DataTypes.Auction({
                owner: address(contango),
                start: uint32(block.timestamp),
                seriesId: SERIES_ID,
                baseId: BASE_ID,
                ilkId: ILK_ID,
                art: 50_000e6,
                ink: 50 ether,
                auctioneer: bot
            }),
            AUCTION_DURATION,
            initialOffer
        );

        (DataTypes.Auction memory auction, , ) = witch.auction(VAULT_ID, bot);

        assertEq(auction.owner, vault.owner);
        assertEq(auction.start, uint32(block.timestamp));
        assertEq(auction.baseId, series.baseId);
        // 100,000 / 2
        assertEq(auction.art, 50_000e6);
        // 100 * 0.5
        assertEq(auction.ink, 50 ether);

        DataTypes.Auction memory auction_ = iWitch.auctions(VAULT_ID);
        assertEq(auction_.owner, auction.owner);
        assertEq(auction_.start, auction.start);
        assertEq(auction_.baseId, auction.baseId);
        assertEq(auction_.art, auction.art);
        assertEq(auction_.ink, auction.ink);

        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);
    }

    function testCancelNonExistentAuction() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.VaultNotUnderAuction.selector,
                VAULT_ID
            )
        );
        witch.cancel(VAULT_ID);
    }

    function testPayBaseNonExistingAuction() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.VaultNotUnderAuction.selector,
                VAULT_ID
            )
        );
        witch.payBase(VAULT_ID, address(0), 0, 0);
    }

    function testPayFYTokenNonExistingAuction() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.VaultNotUnderAuction.selector,
                VAULT_ID
            )
        );
        witch.payFYToken(VAULT_ID, address(0), 0, 0);
    }
}

abstract contract ContangoWitchWithAuction is ContangoWitchWithMetadata {
    using Mocks for *;

    bytes12 internal constant VAULT_ID_2 = "vault2";
    DataTypes.Auction auction;

    function setUp() public virtual override {
        super.setUp();

        _verifyAuctionStarted(VAULT_ID);

        // Test everything on the last moment the witch would be usable
        vm.warp(type(uint32).max);

        cauldron.level.mock(VAULT_ID, -1);

        DataTypes.Vault memory givenVault = vault;
        givenVault.owner = address(witch);
        cauldron.give.mock(VAULT_ID, address(witch), givenVault);

        vm.prank(bot);
        (auction, vault, series) = witch.auction(VAULT_ID, bot);
        // Mocks are not pass by reference, so we need to re-mock
        cauldron.vaults.mock(VAULT_ID, vault);
    }

    function _stubVault(
        bytes12 vaultId,
        uint128 ink,
        uint128 art,
        int256 level
    ) internal {
        DataTypes.Vault memory v = DataTypes.Vault({
            owner: address(contango),
            seriesId: SERIES_ID,
            ilkId: ILK_ID
        });
        DataTypes.Balances memory b = DataTypes.Balances(art, ink);
        cauldron.vaults.mock(vaultId, v);
        cauldron.balances.mock(vaultId, b);
        cauldron.level.mock(vaultId, level);
        cauldron.give.mock(vaultId, address(witch), v);
    }

    function _auctionWasDeleted(bytes12 vaultId) internal {
        DataTypes.Auction memory auction_ = iWitch.auctions(vaultId);
        assertEq(auction_.owner, address(0));
        assertEq(auction_.start, 0);
        assertEq(auction_.baseId, "");
        assertEq(auction_.art, 0);
        assertEq(auction_.ink, 0);
    }

    function _auctionWasUpdated(
        bytes12 vaultId,
        uint128 art,
        uint128 ink
    ) internal {
        DataTypes.Auction memory auction_ = iWitch.auctions(vaultId);
        assertEq(auction_.owner, auction.owner, "owner");
        assertEq(auction_.start, auction.start, "start");
        assertEq(auction_.baseId, auction.baseId, "baseId");
        assertEq(auction_.art, auction.art - art, "art");
        assertEq(auction_.ink, auction.ink - ink, "ink");
    }
}

contract ContangoWitchWithAuctionTest is ContangoWitchWithAuction {
    using Mocks for *;

    function testCalcPayoutForAuctioneer() public {
        uint256 vaultDebt = balances.art;
        uint256 auctionStart = auction.start;

        // 100000 * 0.5 = 50000
        // maxArtIn = (vaultDebt * proportion)

        // 100 * 0.5 * 0.714 = 357
        // (ink * proportion * initialOffer)
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .calcPayout(VAULT_ID, bot, vaultDebt);
        assertEqDecimal(liquidatorCut, 35.7 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        vm.warp(auctionStart + 5 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 300/3600) = 36.8916666667
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(
            liquidatorCut,
            36.89166666666666665 ether,
            18,
            "liquidatorCut"
        );
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        vm.warp(auctionStart + 30 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 1800/3600) = 42.85
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 42.85 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        // Right at auction end
        vm.warp(auctionStart + 1 hours);
        // 100 * 0.5 = 50 (ink * proportion)
        // from now on, the liquidatorCut will not change anymore
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        // After the auction ends the value is fixed
        vm.warp(auctionStart + 4 hours);
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");
    }

    function testCalcPayoutForNonAuctioneer() public {
        address bot2 = address(0xb072);

        // liquidatorCut = 100  * 0.5        * 0.714        * 0.99                       = 35.343
        //                 (ink * proportion * initialOffer * (1 - auctioneerReward))
        // auctioneerCut = 100  * 0.5        * 0.714        * 0.01                       = 0.357
        //                 (ink * proportion * initialOffer * auctioneerReward)
        (uint256 liquidatorCut, uint256 auctioneerCut, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            50_000e6
        );
        assertEq(liquidatorCut, 35.343 ether, "liquidatorCut");
        assertEq(auctioneerCut, 0.357 ether, "auctioneerCut");

        skip(5 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 300/3600) = 36.8916666667
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        (liquidatorCut, auctioneerCut, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            50_000e6
        );
        // 36.8916666667 * 0.99
        assertEq(liquidatorCut, 36.522749999999999984 ether);
        // 36.8916666667 * 0.01
        assertEq(auctioneerCut, 0.368916666666666666 ether);

        skip(25 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 1800/3600) = 42.85
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        (liquidatorCut, auctioneerCut, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            50_000e6
        );
        // 42.85 * 0.99
        assertEq(liquidatorCut, 42.4215 ether);
        // 42.85 * 0.01
        assertEq(auctioneerCut, 0.4285 ether);

        // Right at auction end
        skip(30 minutes);
        // 100 * 0.5 = 50
        // (ink * proportion)
        (liquidatorCut, auctioneerCut, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            50_000e6
        );
        // 50 * 0.99
        assertEq(liquidatorCut, 49.5 ether);
        // 50 * 0.01
        assertEq(auctioneerCut, 0.5 ether);

        // After the auction ends the value is fixed
        skip(1 hours);
        (liquidatorCut, auctioneerCut, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            50_000e6
        );
        assertEq(liquidatorCut, 49.5 ether);
        assertEq(auctioneerCut, 0.5 ether);
    }

    function testAuctionAlreadyExists() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.VaultAlreadyUnderAuction.selector,
                VAULT_ID,
                address(witch)
            )
        );
        witch.auction(VAULT_ID, bot);
    }

    function testCollateralLimits() public {
        // Given
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);

        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 101 ether,
            art: 100_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        // When
        witch.auction(VAULT_ID_2, bot);

        // Then
        (, sum) = witch.limits(ILK_ID, BASE_ID);
        // Max is 100, but the position could be auctioned due to the soft limit
        // Next position will fail
        assertEq(sum, 100.5 ether);

        // Given
        bytes12 otherVaultId = "other vault";
        _stubVault({
            vaultId: otherVaultId,
            ink: 10 ether,
            art: 20_000e6,
            level: -1
        });

        // Expect
        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.CollateralLimitExceeded.selector,
                sum,
                max
            )
        );

        // When
        witch.auction(otherVaultId, bot);
    }

    function testDustLimitProportionUnderDust() public {
        proportion = 0.2e18;
        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer,
            max
        );

        // 20% of this vault would be less than the min of 5k
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 20 ether,
            art: 20_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        (DataTypes.Auction memory auction2, , ) = witch.auction(
            VAULT_ID_2,
            bot
        );

        assertEq(auction2.owner, address(contango));
        assertEq(auction2.start, uint32(block.timestamp));
        assertEq(auction2.baseId, series.baseId);
        // Min amount is put for liquidation
        assertEq(auction2.art, 5_000e6, "art");
        assertEq(auction2.ink, 5 ether, "ink");
    }

    function testDustLimitRemainderUnderDust() public {
        proportion = 0.6e18;
        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer,
            max
        );

        // The remainder (40% of this vault) would be less than the min of 5k
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 10 ether,
            art: 10_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        (DataTypes.Auction memory auction2, , ) = witch.auction(
            VAULT_ID_2,
            bot
        );

        assertEq(auction2.owner, address(contango));
        assertEq(auction2.start, uint32(block.timestamp));
        assertEq(auction2.baseId, series.baseId);
        // 100% of the vault was put for liquidation
        assertEq(auction2.art, 10_000e6, "art");
        assertEq(auction2.ink, 10 ether, "ink");
    }

    function testDustLimitProportionUnderDustAndRemainderUnderDustAfterAdjusting()
        public
    {
        // 50% of this vault would be less than the min of 5k
        // Increasing the liquidated amount to the 5k min would leave a remainder under the limit (9000 - 5000 = 4000)
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 9 ether,
            art: 9_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        (DataTypes.Auction memory auction2, , ) = witch.auction(
            VAULT_ID_2,
            bot
        );

        assertEq(auction2.owner, address(contango));
        assertEq(auction2.start, uint32(block.timestamp));
        assertEq(auction2.baseId, series.baseId);
        // 100% of the vault was put for liquidation
        assertEq(auction2.art, 9_000e6, "art");
        assertEq(auction2.ink, 9 ether, "ink");
    }

    function testVaultDebtBelowDustLimit() public {
        _verifyAuctionStarted(VAULT_ID_2);

        // 4999 is below the min debt of 5k
        _stubVault({vaultId: VAULT_ID_2, ink: 9 ether, art: 4999e6, level: -1});

        (DataTypes.Auction memory auction2, , ) = witch.auction(
            VAULT_ID_2,
            bot
        );

        assertEq(auction2.owner, address(contango));
        assertEq(auction2.start, uint32(block.timestamp));
        assertEq(auction2.baseId, series.baseId);
        // 100% of the vault was put for liquidation
        assertEq(auction2.art, 4999e6, "art");
        assertEq(auction2.ink, 9 ether, "ink");
    }

    function testUpdateLineAndLimitKeepsSum() public {
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);

        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer,
            1
        );

        (uint128 _max, uint128 _sum) = witch.limits(ILK_ID, BASE_ID);

        assertEq(_max, 1);
        // Sum is copied from old values
        assertEq(_sum, 50 ether);
    }

    function testCancelUndercollateralisedAuction() public {
        vm.expectRevert(
            abi.encodeWithSelector(Witch.UnderCollateralised.selector, VAULT_ID)
        );
        witch.cancel(VAULT_ID);
    }

    function testCancelAuction() public {
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);

        cauldron.level.mockAndVerify(VAULT_ID, 0);
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Cancelled(VAULT_ID);

        _verifyAuctionEnded(VAULT_ID, address(contango));

        witch.cancel(VAULT_ID);

        // sum is reduced by auction.ink
        (, sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0);

        _auctionWasDeleted(VAULT_ID);
    }

    function testClearOwnedAuction() public {
        vm.expectRevert(
            abi.encodeWithSelector(Witch.AuctionIsCorrect.selector, VAULT_ID)
        );
        witch.clear(VAULT_ID);
    }

    function testClearVault() public {
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);

        // let's give the vault back to the owner
        address owner = Mocks.mock("owner");
        vault.owner = owner;
        cauldron.vaults.mock(VAULT_ID, vault);

        witch.clear(VAULT_ID);

        // sum is reduced by auction.ink
        (, sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0);

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseNotEnoughBought() public {
        // Bot tries to get all collateral but auction just started
        uint128 minInkOut = 50 ether;
        uint128 maxBaseIn = 50_000e6;

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.NotEnoughBought.selector,
                minInkOut,
                35.7 ether
            )
        );
        witch.payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
    }

    function testPayBaseLeavesDust() public {
        // Bot tries to pay an amount that'd leaves dust
        uint128 maxBaseIn = auction.art - 4999e6;

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );

        vm.expectRevert(
            abi.encodeWithSelector(Witch.LeavesDust.selector, 4999e6, 5000e6)
        );
        witch.payBase(VAULT_ID, bot, 0, maxBaseIn);
    }

    function testPayBasePartial() public {
        // Bot Will pay 40% of the debt (for some reason)
        uint128 maxBaseIn = uint128(auction.art.wmul(0.4e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxBaseIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxBaseIn, balances);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut, "sum");

        _auctionWasUpdated(VAULT_ID, maxBaseIn, minInkOut);
    }

    function testPayBasePartialOnPartiallyLiquidatedVault() public {
        // liquidate 40% of the vault
        testPayBasePartial();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);

        // Bot Will pay another 20% of the debt (for some reason)
        uint128 maxBaseIn = uint128(auction.art.wmul(0.2e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxBaseIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxBaseIn, balances);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut, "sum");

        _auctionWasUpdated(VAULT_ID, maxBaseIn, minInkOut);
    }

    function testPayBaseAll() public {
        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxBaseIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllAndTakesAll() public {
        uint128 maxBaseIn = uint128(auction.art);
        vm.warp(uint256(auction.start) + AUCTION_DURATION);

        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxBaseIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(liquidatorCut, balances.ink.wmul(proportion));
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllOnPartiallyLiquidatedVault() public {
        // liquidate 40% of the vault
        testPayBasePartial();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxBaseIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseOnAnAuctionStartedBySomeoneElse() public {
        address bot2 = address(0xb072);

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot2);
        (uint256 liquidatorCut_, uint256 auctioneerCut_, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            maxBaseIn
        );
        uint128 liquidatorCut = uint128(liquidatorCut_);
        uint128 auctioneerCut = uint128(auctioneerCut_);

        _verifyCollateralBought(
            VAULT_ID,
            bot2,
            liquidatorCut + auctioneerCut,
            maxBaseIn
        );
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            liquidatorCut + auctioneerCut,
            maxBaseIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);

        // Liquidator share
        ilkJoin.exit.mockAndVerify(bot2, liquidatorCut, liquidatorCut);
        // Auctioneer share
        ilkJoin.exit.mockAndVerify(bot, auctioneerCut, auctioneerCut);

        baseJoin.join.mockAndVerify(bot2, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot2, liquidatorCut + auctioneerCut, maxBaseIn);

        vm.prank(bot2);
        (uint256 _liquidatorCut, uint256 _auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot2, liquidatorCut, maxBaseIn);
        assertEq(_liquidatorCut, liquidatorCut);
        assertEq(_auctioneerCut, auctioneerCut);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseOnAnAuctionStartedByMaliciousActor() public {
        address bot2 = address(0xb072);
        address evilAddress = address(0x666);
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 140 ether,
            art: 100_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        vm.prank(bot2);
        (auction, , ) = witch.auction(VAULT_ID_2, evilAddress);

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 liquidatorCut_, uint256 auctioneerCut_, ) = witch.calcPayout(
            VAULT_ID_2,
            bot,
            maxBaseIn
        );
        uint128 liquidatorCut = uint128(liquidatorCut_);
        uint128 auctioneerCut = uint128(auctioneerCut_);

        uint128 totalCut = liquidatorCut + auctioneerCut;

        _verifyCollateralBought(VAULT_ID_2, bot, totalCut, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID_2, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID_2, totalCut, maxBaseIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID_2, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);

        // Auctioneer share
        // Mock is strict, so not mocking it will make it throw, which is what we want
        // ilkJoin.exit.mock(evilAddress, auctioneerCut, auctioneerCut);
        ilkJoin.exit.verify(evilAddress, auctioneerCut);

        // Liquidator share
        ilkJoin.exit.mockAndVerify(bot, totalCut, totalCut);

        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID_2);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID_2, bot, totalCut, maxBaseIn);

        vm.prank(bot);
        (uint256 _liquidatorCut, uint256 _auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID_2, bot, liquidatorCut, maxBaseIn);

        // Liquidator gets all
        assertEq(_liquidatorCut, totalCut);
        assertEq(_auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        _auctionWasDeleted(VAULT_ID_2);
    }

    function testPayFYTokenNotEnoughBought() public {
        // Bot tries to get all collateral but auction just started
        uint128 minInkOut = 50 ether;
        uint128 maxArtIn = 50_000e6;

        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.NotEnoughBought.selector,
                minInkOut,
                35.7 ether
            )
        );
        witch.payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
    }

    function testPayFYTokenLeavesDust() public {
        // Bot tries to pay an amount that'd leaves dust
        uint128 maxArtIn = auction.art - 4999e6;
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        vm.expectRevert(
            abi.encodeWithSelector(Witch.LeavesDust.selector, 4999e6, 5000e6)
        );
        witch.payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
    }

    function testPayFYTokenPartial() public {
        // Bot Will pay 40% of the debt (for some reason)
        uint128 maxArtIn = uint128(auction.art.wmul(0.4e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxArtIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxArtIn, balances);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(artIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut, "sum");

        _auctionWasUpdated(VAULT_ID, maxArtIn, minInkOut);
    }

    function testPayFYTokenPartialOnPartiallyLiquidatedVault() public {
        // liquidate 40% of the vault
        testPayFYTokenPartial();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);

        // Bot Will pay another 20% of the debt (for some reason)
        uint128 maxArtIn = uint128(auction.art.wmul(0.2e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxArtIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxArtIn, balances);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(artIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut, "sum");

        _auctionWasUpdated(VAULT_ID, maxArtIn, minInkOut);
    }

    function testPayFYTokenAllStartedBySomeoneElse() public {
        address bot2 = address(0xb072);

        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot2);
        (uint256 liquidatorCut_, uint256 auctioneerCut_, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            maxArtIn
        );
        uint128 liquidatorCut = uint128(liquidatorCut_);
        uint128 auctioneerCut = uint128(auctioneerCut_);

        _verifyCollateralBought(
            VAULT_ID,
            bot2,
            liquidatorCut + auctioneerCut,
            maxArtIn
        );
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            liquidatorCut + auctioneerCut,
            maxArtIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);

        // Liquidator share
        ilkJoin.exit.mockAndVerify(bot2, liquidatorCut, liquidatorCut);
        // Auctioneer share
        ilkJoin.exit.mockAndVerify(bot, auctioneerCut, auctioneerCut);

        series.fyToken.burn.mockAndVerify(bot2, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot2, liquidatorCut + auctioneerCut, maxArtIn);

        vm.prank(bot2);
        (uint256 _liquidatorCut, uint256 _auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot2, liquidatorCut, maxArtIn);
        assertEq(_liquidatorCut, liquidatorCut);
        assertEq(_auctioneerCut, auctioneerCut);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenAllOnAuctionStartedByMaliciousActor() public {
        address bot2 = address(0xb072);
        address evilAddress = address(0x666);
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 140 ether,
            art: 100_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        vm.prank(bot2);
        (auction, , ) = witch.auction(VAULT_ID_2, evilAddress);

        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 liquidatorCut_, uint256 auctioneerCut_, ) = witch.calcPayout(
            VAULT_ID_2,
            bot,
            maxArtIn
        );
        uint128 liquidatorCut = uint128(liquidatorCut_);
        uint128 auctioneerCut = uint128(auctioneerCut_);

        uint128 totalCut = liquidatorCut + auctioneerCut;

        _verifyCollateralBought(VAULT_ID_2, bot, totalCut, maxArtIn);
        _verifyAuctionEnded(VAULT_ID_2, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID_2, totalCut, maxArtIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID_2, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);

        // Auctioneer share
        // Mock is strict, so not mocking it will make it throw, which is what we want
        // ilkJoin.exit.mock(evilAddress, auctioneerCut, auctioneerCut);
        ilkJoin.exit.verify(evilAddress, auctioneerCut);

        // Liquidator share
        ilkJoin.exit.mockAndVerify(bot, totalCut, totalCut);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID_2);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID_2, bot, totalCut, maxArtIn);

        vm.prank(bot);
        (uint256 _liquidatorCut, uint256 _auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID_2, bot, liquidatorCut, maxArtIn);

        // Liquidator gets all
        assertEq(_liquidatorCut, totalCut);
        assertEq(_auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        _auctionWasDeleted(VAULT_ID_2);
    }

    function testPayFYTokenAll() public {
        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxArtIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mock(VAULT_ID, minInkOut, maxArtIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenAllAndTakesAll() public {
        uint128 maxArtIn = uint128(auction.art);
        vm.warp(uint256(auction.start) + AUCTION_DURATION);

        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxArtIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mock(VAULT_ID, minInkOut, maxArtIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenAllOnPartiallyLiquidatedVault() public {
        // liquidate 40% of the vault
        testPayFYTokenPartial();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);
        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxArtIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mock(VAULT_ID, minInkOut, maxArtIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }
}

contract ContangoWitchWithInsuranceTest is ContangoWitchWithAuction {
    using Mocks for *;

    uint64 maxInsuredProportion = 0.2e18;
    uint64 insurancePremium = 0.02e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(ada);
        witch.setInsuranceLine(
            ILK_ID,
            BASE_ID,
            INSURANCE_AUCTION_DURATION,
            maxInsuredProportion,
            insuranceFund,
            insurancePremium,
            insurancePremiumReceiver
        );
    }

    function testCalcPayoutForAuctioneerWithInsurance() public {
        uint256 vaultDebt = balances.art;
        uint256 auctionStart = auction.start;

        // ensure full top up is considered
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        // 100000 * 0.5 = 50000
        // maxArtIn = (vaultDebt * proportion)

        // 100 * 0.5 * 0.714 * 0.98 = 34.986
        // (ink * proportion * initialOffer * (1 - premium))
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .calcPayout(VAULT_ID, bot, vaultDebt);
        assertEqDecimal(liquidatorCut, 34.986 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        vm.warp(auctionStart + 5 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 300/3600) * 0.98 = 36.1538333333
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed * (1 - premium))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(
            liquidatorCut,
            36.153833333333333317 ether,
            18,
            "liquidatorCut"
        );
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        vm.warp(auctionStart + 30 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 1800/3600) * 0.98 = 41.993
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed * (1 - premium))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 41.993 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        // Right at auction end and start of the insurance auction
        vm.warp(auctionStart + 1 hours);
        // 100 * 0.5 * 0.98 = 49 (ink * proportion)
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 49 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        // After the insurance auction starts, the liquidatorCut will remain fixed
        // 100 * 0.5 = 50

        vm.warp(auctionStart + 1.5 hours);
        // 50000 * (1 - ((1800/7200) * 0.2)) = 47500
        // maxArtIn * (1 - (timeElapsed * maxInsuredProportion))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 47500e6, 6, "artIn");

        vm.warp(auctionStart + 2 hours);
        // 50000 * (1 - ((3600/7200) * 0.2)) = 45000
        // maxArtIn * (1 - (timeElapsed * maxInsuredProportion))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 45000e6, 6, "artIn");

        vm.warp(auctionStart + 2.5 hours);
        // 50000 * (1 - ((5400/7200) * 0.2)) = 42500
        // maxArtIn * (1 - (timeElapsed * maxInsuredProportion))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 42500e6, 6, "artIn");

        // Right at insurance auction end
        vm.warp(auctionStart + 3 hours);
        // 50000 * (1 - 0.2) = 40000
        // maxArtIn * (1 - maxInsuredProportion)
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 40000e6, 6, "artIn");

        // After the auction ends the value is fixed
        vm.warp(auctionStart + 4 hours);
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 40000e6, 6, "artIn");
    }

    function testCalcPayoutForNonAuctioneerWithInsurance() public {
        address bot2 = address(0xb072);

        uint256 vaultDebt = balances.art;
        uint256 auctionStart = auction.start;

        // ensure full top up is considered
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        // 100000 * 0.5 = 50000
        // maxArtIn = (vaultDebt * proportion)

        // liquidatorCut = 100  * 0.5        * 0.714        * 0.99                    * 0.98          = 34.63614
        //                 (ink * proportion * initialOffer * (1 - auctioneerReward)) * (1 - premium)
        // auctioneerCut = 100  * 0.5        * 0.714        * 0.01                                    = 0.357
        //                 (ink * proportion * initialOffer * auctioneerReward)
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .calcPayout(VAULT_ID, bot2, vaultDebt);
        assertEqDecimal(liquidatorCut, 34.63614 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0.357 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        vm.warp(auctionStart + 5 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 300/3600) = 36.8916666667
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        // 36.8916666667 * 0.99 * 0.98 = 35.792295
        assertEqDecimal(
            liquidatorCut,
            35.792294999999999985 ether,
            18,
            "liquidatorCut"
        );
        // 36.8916666667 * 0.01 = 0.3689166667
        assertEqDecimal(
            auctioneerCut,
            0.368916666666666666 ether,
            18,
            "auctioneerCut"
        );
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        vm.warp(auctionStart + 30 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 1800/3600) = 42.85
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        // 42.85 * 0.99 * 0.98 = 41.57307
        assertEqDecimal(liquidatorCut, 41.57307 ether, 18, "liquidatorCut");
        // 42.85 * 0.01 = 0.4285
        assertEqDecimal(auctioneerCut, 0.4285 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        // Right at auction end and start of the insurance auction
        vm.warp(auctionStart + 1 hours);
        // 100 * 0.5 = 50
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        // 50 * 0.99 * 0.98 = 48.51
        assertEqDecimal(liquidatorCut, 48.51 ether, 18, "liquidatorCut");
        // 50 * 0.01 = 0.5
        assertEqDecimal(auctioneerCut, 0.5 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 50000e6, 6, "artIn");

        // After the insurance auction starts, both liquidatorCut and auctioneerCut will remain fixed
        // 100 * 0.5 = 50
        // 50 * 0.99 = 49.5 liquidatorCut
        // 50 * 0.01 = 0.5  auctioneerCut

        vm.warp(auctionStart + 1.5 hours);
        // 50000 * (1 - ((1800/7200) * 0.2)) = 47500
        // maxArtIn * (1 - (timeElapsed * maxInsuredProportion))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 49.5 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0.5 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 47500e6, 6, "artIn");

        vm.warp(auctionStart + 2 hours);
        // 50000 * (1 - ((3600/7200) * 0.2)) = 45000
        // maxArtIn * (1 - (timeElapsed * maxInsuredProportion))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 49.5 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0.5 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 45000e6, 6, "artIn");

        vm.warp(auctionStart + 2.5 hours);
        // 50000 * (1 - ((5400/7200) * 0.2)) = 42500
        // maxArtIn * (1 - (timeElapsed * maxInsuredProportion))
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 49.5 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0.5 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 42500e6, 6, "artIn");

        // Right at insurance auction end
        vm.warp(auctionStart + 3 hours);
        // 50000 * (1 - 0.2) = 40000
        // maxArtIn * (1 - maxInsuredProportion)
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 49.5 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0.5 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 40000e6, 6, "artIn");

        // After the auction ends the value is fixed
        vm.warp(auctionStart + 4 hours);
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot2,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 49.5 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0.5 ether, 18, "auctioneerCut");
        assertEqDecimal(artIn, 40000e6, 6, "artIn");
    }

    function testCalcPayoutForAuctioneerWithInsuranceUpToInsuranceAvailable()
        public
    {
        uint256 vaultDebt = balances.art;
        uint256 auctionStart = auction.start;

        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, 6000e6);

        // 100000 * 0.5 = 50000
        // maxArtIn = (vaultDebt * proportion)

        // After the insurance auction starts, the liquidatorCut will remain fixed
        // 100 * 0.5 = 50

        vm.warp(auctionStart + AUCTION_DURATION + 30 minutes);
        // 50000 * ((1800/7200) * 0.2) = 2500
        // maxArtIn * (timeElapsed * maxInsuredProportion) = topUpAmount
        // min(2500, 6000) = 2500
        // min(topUpAmount, insuranceAvailable) = realTopUpAmount
        // 50000 - 2500 = 47500
        // maxArtIn - realTopUpAmount = artIn
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .calcPayout(VAULT_ID, bot, vaultDebt);
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 47500e6, 6, "artIn");

        vm.warp(auctionStart + AUCTION_DURATION + 1 hours);
        // 50000 * ((3600/7200) * 0.2) = 5000
        // maxArtIn * (timeElapsed * maxInsuredProportion) = topUpAmount
        // min(5000, 6000) = 5000
        // min(topUpAmount, insuranceAvailable) = realTopUpAmount
        // 50000 - 5000 = 45000
        // maxArtIn - realTopUpAmount = artIn
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 45000e6, 6, "artIn");

        vm.warp(auctionStart + AUCTION_DURATION + 1.5 hours);
        // 50000 * ((5400/7200) * 0.2) = 7500
        // maxArtIn * (timeElapsed * maxInsuredProportion) = topUpAmount
        // min(7500, 6000) = 6000
        // min(topUpAmount, insuranceAvailable) = realTopUpAmount
        // 50000 - 6000 = 44000
        // maxArtIn - realTopUpAmount = artIn
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 44000e6, 6, "artIn");

        // Right at insurance auction end
        vm.warp(auctionStart + AUCTION_DURATION + INSURANCE_AUCTION_DURATION);
        // 50000 * 0.2 = 10000
        // maxArtIn * maxInsuredProportion = topUpAmount
        // min(10000, 6000) = 6000
        // min(topUpAmount, insuranceAvailable) = realTopUpAmount
        // 50000 - 6000 = 44000
        // maxArtIn - realTopUpAmount = artIn
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 44000e6, 6, "artIn");

        // After insurance auction ends the value is fixed
        vm.warp(
            auctionStart +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION +
                1 hours
        );
        (liquidatorCut, auctioneerCut, artIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            vaultDebt
        );
        assertEqDecimal(liquidatorCut, 50 ether, 18, "liquidatorCut");
        assertEqDecimal(auctioneerCut, 0, 18, "auctioneerCut");
        assertEqDecimal(artIn, 44000e6, 6, "artIn");
    }

    function testDustLimitProportionUnderDustWithInsurance() public {
        proportion = 0.2e18;
        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer,
            max
        );

        // 20% of this vault would be less than the min of 5k
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 20 ether,
            art: 20_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        (DataTypes.Auction memory auction2, , ) = witch.auction(
            VAULT_ID_2,
            bot
        );

        assertEq(auction2.owner, address(contango));
        assertEq(auction2.start, uint32(block.timestamp));
        assertEq(auction2.baseId, series.baseId);
        // Min amount is put for liquidation
        assertEq(auction2.art, 5_000e6, "art");
        assertEq(auction2.ink, 5 ether, "ink");
    }

    function testDustLimitRemainderUnderDustWithInsurance() public {
        proportion = 0.6e18;
        vm.prank(ada);
        witch.setLineAndLimit(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer,
            max
        );

        // The remainder (40% of this vault) would be less than the min of 5k
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 10 ether,
            art: 10_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        (DataTypes.Auction memory auction2, , ) = witch.auction(
            VAULT_ID_2,
            bot
        );

        assertEq(auction2.owner, address(contango));
        assertEq(auction2.start, uint32(block.timestamp));
        assertEq(auction2.baseId, series.baseId);
        // 100% of the vault was put for liquidation
        assertEq(auction2.art, 10_000e6, "art");
        assertEq(auction2.ink, 10 ether, "ink");
    }

    function testDustLimitProportionUnderDustAndRemainderUnderDustAfterAdjustingWithInsurance()
        public
    {
        // 50% of this vault would be less than the min of 5k
        // Increasing the liquidated amount to the 5k min would leave a remainder under the limit (9000 - 5000 = 4000)
        _stubVault({
            vaultId: VAULT_ID_2,
            ink: 9 ether,
            art: 9_000e6,
            level: -1
        });

        _verifyAuctionStarted(VAULT_ID_2);

        (DataTypes.Auction memory auction2, , ) = witch.auction(
            VAULT_ID_2,
            bot
        );

        assertEq(auction2.owner, address(contango));
        assertEq(auction2.start, uint32(block.timestamp));
        assertEq(auction2.baseId, series.baseId);
        // 100% of the vault was put for liquidation
        assertEq(auction2.art, 9_000e6, "art");
        assertEq(auction2.ink, 9 ether, "ink");
    }

    function testPayBaseLeavesDustWithInsurance() public {
        // Bot tries to pay an amount that'd leaves dust
        uint128 maxBaseIn = auction.art - 4999e6;

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );

        vm.expectRevert(
            abi.encodeWithSelector(Witch.LeavesDust.selector, 4999e6, 5000e6)
        );
        witch.payBase(VAULT_ID, bot, 0, maxBaseIn);
    }

    function testPayBasePartialWithInsurance() public {
        // Bot Will pay 40% of the debt (for some reason)
        uint128 maxBaseIn = uint128(auction.art.wmul(0.4e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxBaseIn,
            balances
        );

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut - premium, "sum");

        _auctionWasUpdated(VAULT_ID, maxBaseIn, minInkOut + premium);
    }

    function testPayBasePartialOnPartiallyLiquidatedVaultWithInsurance()
        public
    {
        // liquidate 40% of the vault
        testPayBasePartialWithInsurance();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);

        // Bot Will pay another 20% of the debt (for some reason)
        uint128 maxBaseIn = uint128(auction.art.wmul(0.2e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxBaseIn,
            balances
        );

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut - premium, "sum");

        _auctionWasUpdated(VAULT_ID, maxBaseIn, minInkOut + premium);
    }

    function testPayBaseAllOnPartiallyLiquidatedVaultWithInsurance() public {
        // liquidate 40% of the vault
        testPayBasePartialWithInsurance();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxBaseIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseOnAnAuctionStartedBySomeoneElseWithInsurance() public {
        address bot2 = address(0xb072);

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot2);
        (uint256 liquidatorCut_, uint256 auctioneerCut_, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            maxBaseIn
        );
        uint128 liquidatorCut = uint128(liquidatorCut_);
        uint128 auctioneerCut = uint128(auctioneerCut_);
        uint128 premium = uint128(
            liquidatorCut.wdiv(1e18 - insurancePremium) - liquidatorCut
        );

        _verifyCollateralBought(
            VAULT_ID,
            bot2,
            liquidatorCut + auctioneerCut + premium,
            maxBaseIn
        );
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            liquidatorCut + auctioneerCut + premium,
            maxBaseIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);

        // Liquidator share
        ilkJoin.exit.mockAndVerify(bot2, liquidatorCut, liquidatorCut);
        // Auctioneer share
        ilkJoin.exit.mockAndVerify(bot, auctioneerCut, auctioneerCut);
        // Insurance Fund share
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);

        baseJoin.join.mockAndVerify(bot2, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(
            VAULT_ID,
            bot2,
            liquidatorCut + auctioneerCut + premium,
            maxBaseIn
        );

        vm.prank(bot2);
        (uint256 _liquidatorCut, uint256 _auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot2, liquidatorCut, maxBaseIn);
        assertEq(_liquidatorCut, liquidatorCut);
        assertEq(_auctioneerCut, auctioneerCut);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllWithInsurance() public {
        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxBaseIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseWithInsuranceNotEnoughBought() public {
        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.NotEnoughBought.selector,
                minInkOut + 1,
                minInkOut
            )
        );
        witch.payBase(VAULT_ID, bot, minInkOut + 1, maxBaseIn);
    }

    function testPayBaseAllAndTakesAllWithInsurance() public {
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION
        );

        // ensure full top up is considered
        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        vm.prank(bot);
        (uint256 minInkOut_, , uint256 maxArtIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            auction.art
        );
        assertEq(maxArtIn, auction.art.wmul(1e18 - maxInsuredProportion));
        uint128 minInkOut = uint128(minInkOut_);
        uint128 maxBaseIn = uint128(maxArtIn);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, auction.art);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        uint128 expectedArtTopUp = auction.art - maxBaseIn;
        uint128 expectedArtRepaid = auction.art - expectedArtTopUp;

        {
            // Reduce balances on the vault
            cauldron.slurp.mockAndVerify(
                VAULT_ID,
                minInkOut,
                auction.art,
                balances
            );
            // Vault returns to it's owner after all the liquidation is done
            cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

            // make fyToken 1:1 with base to make things simpler
            cauldron.debtFromBase.mockAndVerify(
                vault.seriesId,
                maxBaseIn,
                maxBaseIn
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtTopUp,
                expectedArtTopUp
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtRepaid,
                expectedArtRepaid
            );

            ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

            baseJoin.join.mockAndVerify(
                bot,
                expectedArtRepaid,
                expectedArtRepaid
            );

            insuranceFund.insure.mockAndVerify(
                SERIES_ID,
                expectedArtTopUp,
                0,
                expectedArtTopUp
            );

            baseJoin.join.mockAndVerify(
                address(witch),
                expectedArtTopUp,
                expectedArtTopUp
            );
        }

        vm.expectEmit(true, true, true, true);
        emit LiquidationInsured(VAULT_ID, expectedArtTopUp, 0);
        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, auction.art);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut, "liquidatorCut");
        assertEq(liquidatorCut, balances.ink.wmul(proportion), "liquidatorCut");
        assertEq(auctioneerCut, 0, "auctioneerCut");
        assertEq(baseIn, maxArtIn, "baseIn");

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenLeavesDustWithInsurance() public {
        // Bot tries to pay an amount that'd leaves dust
        uint128 maxArtIn = auction.art - 4999e6;
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        vm.expectRevert(
            abi.encodeWithSelector(Witch.LeavesDust.selector, 4999e6, 5000e6)
        );
        witch.payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
    }

    function testPayFYTokenPartialWithInsurance() public {
        // Bot Will pay 40% of the debt (for some reason)
        uint128 maxArtIn = uint128(auction.art.wmul(0.4e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxArtIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxArtIn,
            balances
        );

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(artIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut - premium, "sum");

        _auctionWasUpdated(VAULT_ID, maxArtIn, minInkOut + premium);
    }

    function testPayFYTokenPartialOnPartiallyLiquidatedVaultWithInsurance()
        public
    {
        // liquidate 40% of the vault
        testPayFYTokenPartialWithInsurance();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);

        // Bot Will pay another 20% of the debt (for some reason)
        uint128 maxArtIn = uint128(auction.art.wmul(0.2e18));
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxArtIn);

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxArtIn,
            balances
        );

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(artIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, auction.ink - minInkOut - premium, "sum");

        _auctionWasUpdated(VAULT_ID, maxArtIn, minInkOut + premium);
    }

    function testPayFYTokenAllWithInsurance() public {
        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxArtIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxArtIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenWithInsuranceNotEnoughBought() public {
        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);

        vm.expectRevert(
            abi.encodeWithSelector(
                Witch.NotEnoughBought.selector,
                minInkOut + 1,
                minInkOut
            )
        );
        witch.payFYToken(VAULT_ID, bot, minInkOut + 1, maxArtIn);
    }

    function testPayFYTokenAllAndTakesAllWithInsurance() public {
        uint128 maxArtIn = uint128(auction.art);
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION
        );

        // ensure full top up is considered
        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        vm.prank(bot);
        (uint256 minInkOut_, , uint256 maxArtIn_) = witch.calcPayout(
            VAULT_ID,
            bot,
            maxArtIn
        );
        uint128 minInkOut = uint128(minInkOut_);
        maxArtIn = uint128(maxArtIn_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, auction.art);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        uint128 expectedArtTopUp = auction.art - maxArtIn;
        {
            uint128 expectedArtRepaid = auction.art - expectedArtTopUp;
            // Reduce balances on the vault
            cauldron.slurp.mockAndVerify(
                VAULT_ID,
                minInkOut,
                auction.art,
                balances
            );
            // Vault returns to it's owner after all the liquidation is done
            cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

            // make fyToken 1:1 with base to make things simpler
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtTopUp,
                expectedArtTopUp
            );

            ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

            insuranceFund.insure.mockAndVerify(
                SERIES_ID,
                expectedArtTopUp,
                0,
                expectedArtTopUp
            );

            series.fyToken.burn.mockAndVerify(bot, expectedArtRepaid);

            baseJoin.join.mockAndVerify(
                address(witch),
                expectedArtTopUp,
                expectedArtTopUp
            );
        }

        vm.expectEmit(true, true, true, true);
        emit LiquidationInsured(VAULT_ID, expectedArtTopUp, 0);
        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, auction.art);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(liquidatorCut, balances.ink.wmul(proportion), "liquidatorCut");
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenAllOnPartiallyLiquidatedVaultWithInsurance() public {
        // liquidate 40% of the vault
        testPayFYTokenPartialWithInsurance();
        // Refresh auction copy
        auction = iWitch.auctions(VAULT_ID);
        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxArtIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxArtIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxArtIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);

        series.fyToken.burn.mockAndVerify(bot, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxArtIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenAllStartedBySomeoneElseWithInsurance() public {
        address bot2 = address(0xb072);

        uint128 maxArtIn = uint128(auction.art);
        vm.prank(bot2);
        (uint256 liquidatorCut_, uint256 auctioneerCut_, ) = witch.calcPayout(
            VAULT_ID,
            bot2,
            maxArtIn
        );
        uint128 liquidatorCut = uint128(liquidatorCut_);
        uint128 auctioneerCut = uint128(auctioneerCut_);
        uint128 premium = uint128(
            liquidatorCut.wdiv(1e18 - insurancePremium) - liquidatorCut
        );

        _verifyCollateralBought(
            VAULT_ID,
            bot2,
            liquidatorCut + auctioneerCut + premium,
            maxArtIn
        );
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            liquidatorCut + auctioneerCut + premium,
            maxArtIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);

        // Liquidator share
        ilkJoin.exit.mockAndVerify(bot2, liquidatorCut, liquidatorCut);
        // Auctioneer share
        ilkJoin.exit.mockAndVerify(bot, auctioneerCut, auctioneerCut);
        // Insurance fund share
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);

        series.fyToken.burn.mockAndVerify(bot2, maxArtIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(
            VAULT_ID,
            bot2,
            liquidatorCut + auctioneerCut + premium,
            maxArtIn
        );

        vm.prank(bot2);
        (uint256 _liquidatorCut, uint256 _auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot2, liquidatorCut, maxArtIn);
        assertEq(_liquidatorCut, liquidatorCut);
        assertEq(_auctioneerCut, auctioneerCut);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllAndTakesAllWithInsuranceUseFYTokenBalanceFirst()
        public
    {
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION
        );

        uint128 expectedFyTokenTopUp = 150e6;

        // ensure full top up is considered
        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        vm.prank(bot);
        (uint256 minInkOut_, , uint256 maxArtIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            auction.art
        );
        assertEq(maxArtIn, auction.art.wmul(1e18 - maxInsuredProportion));
        uint128 minInkOut = uint128(minInkOut_);
        uint128 maxBaseIn = uint128(maxArtIn);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, auction.art);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        uint128 expectedArtTopUp = auction.art - maxBaseIn;
        uint128 expectedBaseTopUp = expectedArtTopUp - expectedFyTokenTopUp;
        uint128 expectedArtRepaid = auction.art - expectedArtTopUp;

        {
            // Reduce balances on the vault
            cauldron.slurp.mockAndVerify(
                VAULT_ID,
                minInkOut,
                auction.art,
                balances
            );
            // Vault returns to it's owner after all the liquidation is done
            cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

            // make fyToken 1:1 with base to make things simpler
            cauldron.debtFromBase.mockAndVerify(
                vault.seriesId,
                maxBaseIn,
                maxBaseIn
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtTopUp,
                expectedArtTopUp
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtRepaid,
                expectedArtRepaid
            );

            ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

            insuranceFund.insure.mockAndVerify(
                SERIES_ID,
                expectedArtTopUp,
                expectedFyTokenTopUp,
                expectedBaseTopUp
            );

            series.fyToken.burn.mockAndVerify(
                address(witch),
                expectedFyTokenTopUp
            );

            baseJoin.join.mockAndVerify(
                bot,
                expectedArtRepaid,
                expectedArtRepaid
            );

            baseJoin.join.mockAndVerify(
                address(witch),
                expectedBaseTopUp,
                expectedBaseTopUp
            );
        }

        vm.expectEmit(true, true, true, true);
        emit LiquidationInsured(VAULT_ID, expectedArtTopUp, 0);
        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, auction.art);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut, "liquidatorCut");
        assertEq(liquidatorCut, balances.ink.wmul(proportion), "liquidatorCut");
        assertEq(auctioneerCut, 0, "auctioneerCut");
        assertEq(baseIn, maxArtIn, "baseIn");

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayFYTokenAllAndTakesAllWithInsuranceUseFYTokenBalanceFirst()
        public
    {
        uint128 maxArtIn = uint128(auction.art);
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION
        );

        uint128 expectedFyTokenTopUp = 150e6;

        // ensure full top up is considered
        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        uint128 minInkOut;
        {
            vm.prank(bot);
            (uint256 minInkOut_, , uint256 maxArtIn_) = witch.calcPayout(
                VAULT_ID,
                bot,
                maxArtIn
            );
            minInkOut = uint128(minInkOut_);
            maxArtIn = uint128(maxArtIn_);
        }

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, auction.art);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        uint128 expectedArtTopUp = auction.art - maxArtIn;
        {
            uint128 expectedBaseTopUp = expectedArtTopUp - expectedFyTokenTopUp;
            uint128 expectedArtRepaid = auction.art - expectedArtTopUp;

            // Reduce balances on the vault
            cauldron.slurp.mockAndVerify(
                VAULT_ID,
                minInkOut,
                auction.art,
                balances
            );
            // Vault returns to it's owner after all the liquidation is done
            cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

            // make fyToken 1:1 with base to make things simpler
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtTopUp,
                expectedArtTopUp
            );

            ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

            insuranceFund.insure.mockAndVerify(
                SERIES_ID,
                expectedArtTopUp,
                expectedFyTokenTopUp,
                expectedBaseTopUp
            );

            series.fyToken.burn.mockAndVerify(
                address(witch),
                expectedFyTokenTopUp
            );

            series.fyToken.burn.mockAndVerify(bot, expectedArtRepaid);

            baseJoin.join.mockAndVerify(
                address(witch),
                expectedBaseTopUp,
                expectedBaseTopUp
            );
        }

        vm.expectEmit(true, true, true, true);
        emit LiquidationInsured(VAULT_ID, expectedArtTopUp, 0);
        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, auction.art);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payFYToken(VAULT_ID, bot, minInkOut, maxArtIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(liquidatorCut, balances.ink.wmul(proportion), "liquidatorCut");
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxArtIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllAndTakesAllWithInsuranceUpToAuctionArt() public {
        // ensure full top up is considered
        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        // halfway through the auction
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                (INSURANCE_AUCTION_DURATION / 2)
        );

        vm.prank(bot);
        (uint256 minInkOut_, , uint256 maxArtIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            auction.art
        );
        assertEq(maxArtIn, auction.art.wmul(1e18 - maxInsuredProportion / 2));
        uint128 minInkOut = uint128(minInkOut_);
        uint128 maxBaseIn = uint128(maxArtIn);

        // advance to end of auction, previous quote will be outdated and liquidator will overpay
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, auction.art);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        uint128 expectedArtTopUp = auction.art - maxBaseIn;
        uint128 expectedArtRepaid = auction.art - expectedArtTopUp;

        {
            // Reduce balances on the vault
            cauldron.slurp.mockAndVerify(
                VAULT_ID,
                minInkOut,
                auction.art,
                balances
            );
            // Vault returns to it's owner after all the liquidation is done
            cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

            // make fyToken 1:1 with base to make things simpler
            cauldron.debtFromBase.mockAndVerify(
                vault.seriesId,
                maxBaseIn,
                maxBaseIn
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtTopUp,
                expectedArtTopUp
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtRepaid,
                expectedArtRepaid
            );

            ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

            baseJoin.join.mockAndVerify(
                bot,
                expectedArtRepaid,
                expectedArtRepaid
            );

            insuranceFund.insure.mockAndVerify(
                SERIES_ID,
                expectedArtTopUp,
                0,
                expectedArtTopUp
            );

            baseJoin.join.mockAndVerify(
                address(witch),
                expectedArtTopUp,
                expectedArtTopUp
            );
        }

        vm.expectEmit(true, true, true, true);
        emit LiquidationInsured(VAULT_ID, expectedArtTopUp, 0);
        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, auction.art);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut, "liquidatorCut");
        assertEq(liquidatorCut, balances.ink.wmul(proportion), "liquidatorCut");
        assertEq(auctioneerCut, 0, "auctioneerCut");
        assertEq(baseIn, maxBaseIn, "baseIn");

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllWithInsuranceUsingDefaultPremium() public {
        uint64 defaultInsurancePremium = 0.05e18;

        vm.startPrank(ada);
        witch.setDefaultInsurancePremium(defaultInsurancePremium);
        witch.setInsuranceLine({
            ilkId: ILK_ID,
            baseId: BASE_ID,
            duration: INSURANCE_AUCTION_DURATION,
            maxInsuredProportion: maxInsuredProportion,
            insuranceFund: insuranceFund,
            insurancePremium: 0,
            insurancePremiumReceiver: insurancePremiumReceiver
        });
        vm.stopPrank();

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - defaultInsurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxBaseIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllWithoutInsuranceButChargingPremium() public {
        vm.startPrank(ada);
        witch.setInsuranceLine({
            ilkId: ILK_ID,
            baseId: BASE_ID,
            duration: 0,
            maxInsuredProportion: 0,
            insuranceFund: insuranceFund,
            insurancePremium: insurancePremium,
            insurancePremiumReceiver: insurancePremiumReceiver
        });
        vm.stopPrank();

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);
        uint128 premium = uint128(
            minInkOut.wdiv(1e18 - insurancePremium) - minInkOut
        );

        _verifyCollateralBought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(
            VAULT_ID,
            minInkOut + premium,
            maxBaseIn,
            balances
        );
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        ilkJoin.exit.mockAndVerify(insurancePremiumReceiver, premium, premium);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut + premium, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllWithoutInsuranceEnabledAndNotChargingPremium()
        public
    {
        vm.startPrank(ada);
        witch.setInsuranceLineStatus(ILK_ID, BASE_ID, true);
        vm.stopPrank();

        uint128 maxBaseIn = uint128(auction.art);
        vm.prank(bot);
        (uint256 minInkOut_, , ) = witch.calcPayout(VAULT_ID, bot, maxBaseIn);
        uint128 minInkOut = uint128(minInkOut_);

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, maxBaseIn);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        // Reduce balances on the vault
        cauldron.slurp.mockAndVerify(VAULT_ID, minInkOut, maxBaseIn, balances);
        // Vault returns to it's owner after all the liquidation is done
        cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(vault.seriesId, maxBaseIn, maxBaseIn);

        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);
        baseJoin.join.mockAndVerify(bot, maxBaseIn, maxBaseIn);

        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, maxBaseIn);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut);
        assertEq(auctioneerCut, 0);
        assertEq(baseIn, maxBaseIn);

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }

    function testPayBaseAllAndTakesAllWithInsuranceInsufficientInsuranceAvailable()
        public
    {
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION
        );

        // ensure full top up is considered
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        vm.prank(bot);
        (uint256 minInkOut_, , uint256 maxArtIn) = witch.calcPayout(
            VAULT_ID,
            bot,
            auction.art
        );
        assertEq(maxArtIn, auction.art.wmul(1e18 - maxInsuredProportion));
        uint128 minInkOut = uint128(minInkOut_);
        uint128 maxBaseIn = uint128(maxArtIn);

        uint128 expectedArtTopUp = auction.art - maxBaseIn;

        // make fyToken 1:1 with base to make things simpler
        cauldron.debtFromBase.mockAndVerify(
            vault.seriesId,
            maxBaseIn,
            maxBaseIn
        );
        cauldron.debtToBase.mockAndVerify(
            vault.seriesId,
            expectedArtTopUp,
            expectedArtTopUp
        );

        insuranceFund.insure.mockAndVerify(
            SERIES_ID,
            expectedArtTopUp,
            0,
            expectedArtTopUp - 1
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IContangoWitch.InsufficientInsuranceAvailable.selector,
                SERIES_ID,
                expectedArtTopUp,
                expectedArtTopUp - 1
            )
        );

        vm.prank(bot);
        witch.payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
    }

    function testPayBaseAllAndTakesAllWithInsuranceAndVariableRate() public {
        vm.warp(
            uint256(auction.start) +
                AUCTION_DURATION +
                INSURANCE_AUCTION_DURATION
        );

        // ensure full top up is considered
        (IJoin ilkJoin, IJoin baseJoin) = ladle.mockJoinSetUp(series, vault);
        insuranceFund.insuranceAvailable.mockAndVerify(SERIES_ID, auction.art);

        uint256 variableRate = 0.01e18;

        vm.prank(bot);
        (uint256 minInkOut_, , uint256 maxArtIn_) = witch.calcPayout(
            VAULT_ID,
            bot,
            auction.art
        );
        assertEq(maxArtIn_, auction.art.wmul(1e18 - maxInsuredProportion));
        uint128 minInkOut = uint128(minInkOut_);
        uint128 maxArtIn = uint128(maxArtIn_);
        uint128 maxBaseIn = uint128(maxArtIn_.wmul(1e18 + variableRate));

        _verifyCollateralBought(VAULT_ID, bot, minInkOut, auction.art);
        _verifyAuctionEnded(VAULT_ID, address(contango));

        uint128 expectedArtTopUp = auction.art - maxArtIn;
        uint128 expectedArtRepaid = auction.art - expectedArtTopUp;
        uint128 expectedTopUpVariableRate = uint128(
            expectedArtTopUp.wmul(variableRate)
        );
        uint128 expectedArtRepaidVariableRate = uint128(
            expectedArtRepaid.wmul(variableRate)
        );

        {
            // Reduce balances on the vault
            cauldron.slurp.mockAndVerify(
                VAULT_ID,
                minInkOut,
                auction.art,
                balances
            );
            // Vault returns to it's owner after all the liquidation is done
            cauldron.give.mockAndVerify(VAULT_ID, address(contango), vault);

            cauldron.debtFromBase.mockAndVerify(
                vault.seriesId,
                maxBaseIn,
                maxArtIn
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtTopUp,
                expectedArtTopUp + expectedTopUpVariableRate
            );
            cauldron.debtToBase.mockAndVerify(
                vault.seriesId,
                expectedArtRepaid,
                expectedArtRepaid + expectedArtRepaidVariableRate
            );

            ilkJoin.exit.mockAndVerify(bot, minInkOut, minInkOut);

            baseJoin.join.mockAndVerify(
                bot,
                expectedArtRepaid + expectedArtRepaidVariableRate,
                expectedArtRepaid + expectedArtRepaidVariableRate
            );

            insuranceFund.insure.mockAndVerify(
                SERIES_ID,
                expectedArtTopUp + expectedTopUpVariableRate,
                0,
                expectedArtTopUp + expectedTopUpVariableRate
            );

            baseJoin.join.mockAndVerify(
                address(witch),
                expectedArtTopUp + expectedTopUpVariableRate,
                expectedArtTopUp + expectedTopUpVariableRate
            );
        }

        vm.expectEmit(true, true, true, true);
        emit LiquidationInsured(
            VAULT_ID,
            expectedArtTopUp,
            expectedTopUpVariableRate
        );
        vm.expectEmit(true, true, true, true);
        emit Ended(VAULT_ID);
        vm.expectEmit(true, true, true, true);
        emit Bought(VAULT_ID, bot, minInkOut, auction.art);

        vm.prank(bot);
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 baseIn) = witch
            .payBase(VAULT_ID, bot, minInkOut, maxBaseIn);
        assertEq(liquidatorCut, minInkOut, "liquidatorCut");
        assertEq(liquidatorCut, balances.ink.wmul(proportion), "liquidatorCut");
        assertEq(auctioneerCut, 0, "auctioneerCut");
        assertEq(baseIn, maxBaseIn, "baseIn");

        // sum is reduced by auction.ink
        (, uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0, "sum");

        _auctionWasDeleted(VAULT_ID);
    }
}
