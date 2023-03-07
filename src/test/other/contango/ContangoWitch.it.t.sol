// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";

import "../../utils/TestConstants.sol";
import "../../utils/Mocks.sol";

import "src/other/contango/interfaces/IContangoLadle.sol";
import "src/other/contango/ContangoWitch.sol";

contract ContangoWitchIntegrationTest is Test, TestConstants {
    using Cast for *;
    using Math for *;
    using Mocks for *;

    bytes12 internal constant VAULT_ID = "vault";
    bytes6 internal constant INK_SERIES_ID = FYETH2303;
    bytes6 internal constant ART_SERIES_ID = FYUSDC2303;
    uint32 internal constant INSURANCE_AUCTION_DURATION = 20 minutes;

    address internal constant CONTANGO =
        0x30E7348163016B3b6E1621A3Cb40e8CF33CE97db;
    address internal constant WITCH =
        0x89343a24a217172A569A0bD68763Bf0671A3efd8;

    address internal trader = address(0xbadb01);
    address internal bot = address(0xb07);
    address internal auctioneer = address(0x5a1e5);
    address internal insurancePremiumReceiver = address(0xfee);

    uint64 internal maxInsuredProportion = 0.2e18;
    uint64 internal insurancePremium = 0.02e18;

    IContangoLadle internal ladle;
    ICauldron internal cauldron;
    IContangoInsuranceFund internal insuranceFund;
    ContangoWitch internal witch;

    DataTypes.Auction internal auction;
    DataTypes.Line internal line;
    DataTypes.Vault internal vault;
    DataTypes.Series internal artSeries;
    DataTypes.Series internal inkSeries;

    function setUp() public {
        vm.createSelectFork(ARBITRUM, 67284600);

        // Contango specific versions
        addresses[ARBITRUM][LADLE] = 0x93343C08e2055b7793a3336d659Be348FC1B08f9;
        addresses[ARBITRUM][
            CAULDRON
        ] = 0x44386ddB4C44E7CB8981f97AF89E928Ddd4258DD;

        ladle = IContangoLadle(addresses[ARBITRUM][LADLE]);
        cauldron = ICauldron(addresses[ARBITRUM][CAULDRON]);

        vm.prank(CONTANGO);
        vault = ladle.deterministicBuild(
            VAULT_ID,
            ART_SERIES_ID,
            INK_SERIES_ID
        );

        artSeries = cauldron.series(ART_SERIES_ID);
        inkSeries = cauldron.series(INK_SERIES_ID);

        // TODO witch replacement and insurance fund mocking can be replaced after deployment
        // replace witch and configure insurance
        vm.etch(
            address(WITCH),
            address(new ContangoWitch(cauldron, ladle)).code
        );
        witch = ContangoWitch(WITCH);

        insuranceFund = IContangoInsuranceFund(
            Mocks.mock("ContangoInsuranceFund")
        );

        vm.startPrank(addresses[ARBITRUM][TIMELOCK]);
        witch.grantRole(
            ContangoWitch.setInsuranceLine.selector,
            addresses[ARBITRUM][TIMELOCK]
        );

        witch.setInsuranceLine({
            ilkId: INK_SERIES_ID,
            baseId: artSeries.baseId,
            duration: INSURANCE_AUCTION_DURATION,
            maxInsuredProportion: maxInsuredProportion,
            insuranceFund: insuranceFund,
            insurancePremium: insurancePremium,
            insurancePremiumReceiver: insurancePremiumReceiver
        });
        vm.stopPrank();
    }

    // ================================ tests ================================

    function testPayBaseAllWithInsurance() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        _liquidate({expectedTopUp: 0, payFunction: _payBase});
    }

    function testPayBaseAllWithInsuranceAtEndOfRegularAuction() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration);

        _liquidate({expectedTopUp: 0, payFunction: _payBase});
    }

    function testPayBaseAllAndTakesAllWithInsurance() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + 1);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 1e18,
            insureWithBasePercentage: 1e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payBase});
    }

    function testPayBaseAllAndTakesAllWithInsuranceAtEndOfInsuranceAuction()
        public
    {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + INSURANCE_AUCTION_DURATION);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 1e18,
            insureWithBasePercentage: 0.5e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payBase});
    }

    function testPayBaseAllAndTakesAllWithInsurancePastEndOfInsuranceAuction()
        public
    {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(
            auction.start + line.duration + INSURANCE_AUCTION_DURATION + 1 hours
        );
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 1e18,
            insureWithBasePercentage: 0
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payBase});
    }

    function testPayBaseAllAndTakesAllWithInsuranceUpToAvailablePercentage()
        public
    {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + 1);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 0.5e18,
            insureWithBasePercentage: 1e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payBase});
    }

    function testPayBaseAllAndTakesAllWithInsuranceNotAvailable() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + 1);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 0,
            insureWithBasePercentage: 1e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payBase});
    }

    function testPayFYTokenAllWithInsurance() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        _liquidate({expectedTopUp: 0, payFunction: _payFYToken});
    }

    function testPayFYTokenAllWithInsuranceAtEndOfRegularAuction() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration);

        _liquidate({expectedTopUp: 0, payFunction: _payFYToken});
    }

    function testPayFYTokenAllAndTakesAllWithInsurance() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + 1);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 1e18,
            insureWithBasePercentage: 1e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payFYToken});
    }

    function testPayFYTokenAllAndTakesAllWithInsuranceAtEndOfInsuranceAuction()
        public
    {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + INSURANCE_AUCTION_DURATION);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 1e18,
            insureWithBasePercentage: 0.5e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payFYToken});
    }

    function testPayFYTokenAllAndTakesAllWithInsurancePastEndOfInsuranceAuction()
        public
    {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(
            auction.start + line.duration + INSURANCE_AUCTION_DURATION + 1 hours
        );
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 1e18,
            insureWithBasePercentage: 0
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payFYToken});
    }

    function testPayFYTokenAllAndTakesAllWithInsuranceUpToAvailablePercentage()
        public
    {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + 1);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 0.5e18,
            insureWithBasePercentage: 1e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payFYToken});
    }

    function testPayFYTokenAllAndTakesAllWithInsuranceNotAvailable() public {
        _enterVaultAtCRLimit(100e6);

        _startAuction();

        vm.warp(auction.start + line.duration + 1);
        uint128 expectedTopUp = _mockInsuranceFund({
            availablePercentage: 0,
            insureWithBasePercentage: 1e18
        });

        _liquidate({expectedTopUp: expectedTopUp, payFunction: _payFYToken});
    }

    // ================================ helpers ================================

    function _enterVaultAtCRLimit(uint256 art) private {
        IPool inkPool = IPool(ladle.pools(INK_SERIES_ID));

        DataTypes.SpotOracle memory spotOracle = cauldron.spotOracles(
            artSeries.baseId,
            vault.ilkId
        );

        // quote
        (uint256 spotPrice, ) = spotOracle.oracle.get(
            vault.ilkId,
            artSeries.baseId,
            1 ether
        );
        uint256 ink = ((art * spotOracle.ratio * 1e12) / spotPrice);
        uint256 requiredInkBase = inkPool.buyFYTokenPreview(ink.u128());

        // enter
        deal(inkSeries.fyToken.underlying(), CONTANGO, requiredInkBase);
        vm.startPrank(CONTANGO);
        IERC20(inkSeries.fyToken.underlying()).transfer(
            address(inkPool),
            requiredInkBase
        );

        inkPool.buyFYToken({
            to: address(ladle.joins(INK_SERIES_ID)),
            fyTokenOut: ink.u128(),
            max: type(uint128).max
        });

        ladle.pour(VAULT_ID, trader, ink.i128(), art.i128());
        vm.stopPrank();

        // assert
        assertEq(cauldron.level(VAULT_ID), 0, "level");
    }

    function _startAuction() private {
        IContangoWitchListener(CONTANGO).auctionStarted.mockAndVerify(VAULT_ID);
        cauldron.level.mockAndVerify(VAULT_ID, -1);
        (auction, , ) = witch.auction(VAULT_ID, auctioneer);

        (line.duration, line.vaultProportion, line.collateralProportion) = witch
            .lines(auction.ilkId, auction.baseId);
    }

    function _liquidate(
        uint128 expectedTopUp,
        function(uint256, uint256) payFunction
    ) private {
        address inkUnderlying = inkSeries.fyToken.underlying();
        IFYToken inkFYToken = inkSeries.fyToken;

        // quote
        (uint256 liquidatorCut, uint256 auctioneerCut, uint256 artIn) = witch
            .calcPayout(VAULT_ID, bot, auction.art);
        uint256 expectedPremium = _premium(liquidatorCut);

        IContangoWitchListener(CONTANGO).collateralBought.mockAndVerify(
            VAULT_ID,
            bot,
            liquidatorCut + auctioneerCut + expectedPremium,
            artIn + expectedTopUp
        );

        // liquidate
        IContangoWitchListener(CONTANGO).auctionEnded.mockAndVerify(
            VAULT_ID,
            CONTANGO
        );

        payFunction(liquidatorCut, artIn);

        // assert
        uint256 decimals = IERC20Metadata(inkUnderlying).decimals();
        assertEqDecimal(
            inkFYToken.balanceOf(bot),
            liquidatorCut,
            decimals,
            "liquidatorCut"
        );
        assertEqDecimal(
            inkFYToken.balanceOf(auctioneer),
            auctioneerCut,
            decimals,
            "auctioneerCut"
        );
        assertEqDecimal(
            inkFYToken.balanceOf(insurancePremiumReceiver),
            expectedPremium,
            decimals,
            "premium"
        );
    }

    function _payBase(uint256 liquidatorCut, uint256 artIn) private {
        uint128 baseIn = cauldron.debtToBase(ART_SERIES_ID, artIn.u128());
        address artUnderlying = artSeries.fyToken.underlying();

        deal(artUnderlying, bot, baseIn);

        vm.startPrank(bot);
        IERC20(artUnderlying).transfer(
            address(ladle.joins(artSeries.baseId)),
            baseIn
        );

        witch.payBase(VAULT_ID, bot, liquidatorCut.u128(), baseIn);
        vm.stopPrank();
    }

    function _payFYToken(uint256 liquidatorCut, uint256 artIn) private {
        deal(address(artSeries.fyToken), bot, artIn);

        vm.startPrank(bot);
        artSeries.fyToken.transfer(address(artSeries.fyToken), artIn);

        witch.payFYToken(VAULT_ID, bot, liquidatorCut.u128(), artIn.u128());
        vm.stopPrank();
    }

    function _premium(
        uint256 liquidatorCut
    ) private view returns (uint256 premium) {
        if (block.timestamp <= auction.start + line.duration) {
            premium =
                liquidatorCut.wdiv(1e18 - insurancePremium) -
                liquidatorCut;
        }
    }

    function _mockInsuranceFund(
        uint256 availablePercentage,
        uint256 insureWithBasePercentage
    ) private returns (uint128 expectedTopUp) {
        // quote
        uint256 elapsed = (block.timestamp - (auction.start + line.duration));
        uint256 cappedElapsed = elapsed < INSURANCE_AUCTION_DURATION
            ? elapsed
            : INSURANCE_AUCTION_DURATION;
        expectedTopUp = cappedElapsed
            .wdiv(INSURANCE_AUCTION_DURATION)
            .wmul(maxInsuredProportion)
            .wmul(auction.art)
            .u128();
        expectedTopUp = expectedTopUp.wmul(availablePercentage).u128();

        // mock
        insuranceFund.insuranceAvailable.mockAndVerify(
            ART_SERIES_ID,
            expectedTopUp
        );

        uint256 expectedFYTokenTopUp = expectedTopUp.wmul(
            1e18 - insureWithBasePercentage
        );
        uint256 expectedBaseTopUp = cauldron.debtToBase(
            ART_SERIES_ID,
            expectedTopUp.wmulup(insureWithBasePercentage).u128()
        );

        if (expectedTopUp > 0) {
            insuranceFund.insure.mockAndVerify(
                ART_SERIES_ID,
                cauldron.debtToBase(ART_SERIES_ID, expectedTopUp),
                expectedFYTokenTopUp.u128(),
                expectedBaseTopUp
            );
        }

        // insure
        // with fyToken
        if (expectedFYTokenTopUp > 0) {
            deal(
                address(artSeries.fyToken),
                address(insuranceFund),
                expectedFYTokenTopUp
            );

            vm.prank(address(insuranceFund));
            artSeries.fyToken.transfer(
                address(artSeries.fyToken),
                expectedFYTokenTopUp
            );
        }

        // with base
        if (expectedBaseTopUp > 0) {
            address underlying = artSeries.fyToken.underlying();
            deal(underlying, address(insuranceFund), expectedBaseTopUp);

            address join = address(ladle.joins(artSeries.baseId));
            vm.prank(address(insuranceFund));
            IERC20(underlying).transfer(join, expectedBaseTopUp);
        }
    }
}