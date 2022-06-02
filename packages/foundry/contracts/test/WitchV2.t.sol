// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./utils/Test.sol";
import "./utils/TestConstants.sol";
// import "./utils/Utilities.sol";
import "./utils/Mocks.sol";

import "../WitchV2.sol";

abstract contract WitchV2StateZero is Test, TestConstants {
    using Mocks for *;

    event Auctioned(bytes12 indexed vaultId, uint256 indexed start);
    event Cancelled(bytes12 indexed vaultId);
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
    event LimitSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint96 max,
        uint24 dust,
        uint8 dec
    );
    event Point(bytes32 indexed param, address indexed value);

    bytes12 internal constant VAULT_ID = "vault";
    bytes6 internal constant ILK_ID = ETH;
    bytes6 internal constant BASE_ID = USDC;
    bytes6 internal constant SERIES_ID = FYETH2206;
    uint32 internal constant AUCTION_DURATION = 1 hours;

    // address internal admin;
    address internal deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    address internal ada = address(0xada);
    address internal bob = address(0xb0b);
    address internal bad = address(0xbad);
    address internal cool = address(0xc001);

    ICauldron internal cauldron;
    ILadle internal ladle;

    WitchV2 internal witch;

    function setUp() public virtual {
        cauldron = ICauldron(Mocks.mock("Cauldron"));
        ladle = ILadle(Mocks.mock("Ladle"));

        vm.startPrank(ada);
        witch = new WitchV2(cauldron, ladle);
        witch.grantRole(WitchV2.point.selector, ada);
        witch.grantRole(WitchV2.setLine.selector, ada);
        witch.grantRole(WitchV2.setLimit.selector, ada);
        vm.stopPrank();

        vm.label(ada, "ada");
        vm.label(bob, "bob");
    }
}

contract WitchV2StateZeroTest is WitchV2StateZero {
    function testPointRequiresAuth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        witch.point("ladle", bad);
    }

    function testPointRequiresLadle() public {
        vm.prank(ada);
        vm.expectRevert("Unrecognized");
        witch.point("cauldron", bad);
    }

    function testPoint() public {
        vm.expectEmit(true, true, false, true);
        emit Point("ladle", cool);

        vm.prank(ada);
        witch.point("ladle", cool);

        assertEq(address(witch.ladle()), cool);
    }

    function testSetLineRequiresAuth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        witch.setLine("", "", 0, 0, 0);
    }

    function testSetLineRequiresInitialOfferTooHigh() public {
        vm.prank(ada);
        vm.expectRevert("InitialOffer above 100%");
        witch.setLine("", "", 0, 0, 1e18 + 1);
    }

    function testSetLineRequiresProportionTooHigh() public {
        vm.prank(ada);
        vm.expectRevert("Proportion above 100%");
        witch.setLine("", "", 0, 1e18 + 1, 0);
    }

    function testSetLineRequiresInitialOfferTooLow() public {
        vm.prank(ada);
        vm.expectRevert("InitialOffer below 1%");
        witch.setLine("", "", 0, 0, 0.01e18 - 1);
    }

    function testSetLineRequiresProportionTooLow() public {
        vm.prank(ada);
        vm.expectRevert("Proportion below 1%");
        witch.setLine("", "", 0, 0.01e18 - 1, 0);
    }

    function testSetLine() public {
        uint64 proportion = 0.5e18;
        uint64 initialOffer = 0.75e18;

        vm.expectEmit(true, true, false, true);
        emit LineSet(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer
        );

        vm.prank(ada);
        witch.setLine(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer
        );

        (uint32 _duration, uint64 _proportion, uint64 _initialOffer) = witch
            .lines(ILK_ID, BASE_ID);

        assertEq(_duration, AUCTION_DURATION);
        assertEq(_proportion, proportion);
        assertEq(_initialOffer, initialOffer);
    }

    function testSetLimitRequiresAuth() public {
        vm.prank(bob);
        vm.expectRevert("Access denied");
        witch.setLimit("", "", 0, 0, 0);
    }

    function testSetLimit() public {
        uint96 max = 1;
        uint24 dust = 2;
        uint8 dec = 3;

        vm.expectEmit(true, true, false, true);
        emit LimitSet(ILK_ID, BASE_ID, max, dust, dec);

        vm.prank(ada);
        witch.setLimit(ILK_ID, BASE_ID, max, dust, dec);

        (uint96 _max, uint24 _dust, uint8 _dec, uint128 _sum) = witch.limits(
            ILK_ID,
            BASE_ID
        );

        assertEq(_max, max);
        assertEq(_dust, dust);
        assertEq(_dec, dec);
        assertEq(_sum, 0);
    }
}

abstract contract WitchV2WithMetadata is WitchV2StateZero {
    using Mocks for *;

    DataTypes.Vault vault;
    DataTypes.Series series;
    DataTypes.Balances balances;

    uint96 max = 100e12;
    uint24 dust = 5000;
    uint8 dec = 6;

    uint64 proportion = 0.5e18;
    uint64 initialOffer = 0.714e18;

    function setUp() public virtual override {
        super.setUp();

        vault = DataTypes.Vault({
            owner: bob,
            seriesId: SERIES_ID,
            ilkId: ILK_ID
        });

        series = DataTypes.Series({
            fyToken: IFYToken(address(0xf140)),
            baseId: BASE_ID,
            maturity: uint32(block.timestamp + 30 days)
        });

        balances = DataTypes.Balances({art: 100_000e6, ink: 100 ether});

        cauldron.vaults.mock(VAULT_ID, vault);
        cauldron.series.mock(SERIES_ID, series);
        cauldron.balances.mock(VAULT_ID, balances);

        vm.startPrank(ada);
        witch.setLimit(ILK_ID, BASE_ID, max, dust, dec);
        witch.setLine(
            ILK_ID,
            BASE_ID,
            AUCTION_DURATION,
            proportion,
            initialOffer
        );
        vm.stopPrank();
    }
}

contract WitchV2WithMetadataTest is WitchV2WithMetadata {
    using Mocks for *;

    function testCalcPayout() public {
        // 100 * 0.5 * 0.714 = 35.7
        // (ink * proportion * initialOffer)
        assertEq(witch.calcPayout(VAULT_ID, 50_000e6), 35.7 ether);

        skip(5 minutes);
        // Nothing changes as auction was never started
        assertEq(witch.calcPayout(VAULT_ID, 50_000e6), 35.7 ether);
    }

    function testCalcPayoutFuzzInitialOffer(uint64 io) public {
        vm.assume(io <= 1e18 && io >= 0.01e18);

        vm.prank(ada);
        witch.setLine(ILK_ID, BASE_ID, AUCTION_DURATION, proportion, io);

        uint256 inkOut = witch.calcPayout(VAULT_ID, 50_000e6);

        assertLe(inkOut, 50 ether);
        assertGe(inkOut, 0.5 ether);
    }

    function testCalcPayoutFuzzElapsed(uint16 elapsed) public {
        skip(elapsed);

        uint256 inkOut = witch.calcPayout(VAULT_ID, 50_000e6);

        assertLe(inkOut, 50 ether);
    }

    function testVaultNotUndercollateralised() public {
        cauldron.level.mock(VAULT_ID, 0);
        vm.expectRevert("Not undercollateralized");
        witch.auction(VAULT_ID);
    }

    function testCanAuctionVault() public {
        cauldron.level.mock(VAULT_ID, -1);
        cauldron.give.mock(VAULT_ID, address(witch), vault);
        cauldron.give.verify(VAULT_ID, address(witch));

        vm.expectEmit(true, true, true, true);
        emit Auctioned(VAULT_ID, uint32(block.timestamp));

        WitchV2.Auction memory auction = witch.auction(VAULT_ID);

        assertEq(auction.owner, vault.owner);
        assertEq(auction.start, uint32(block.timestamp));
        assertEq(auction.baseId, series.baseId);
        // 100,000 / 2
        assertEq(auction.art, 50_000e6);
        // 100 * 0.5
        assertEq(auction.ink, 50 ether);

        (
            address owner,
            uint32 start,
            bytes6 baseId,
            uint128 ink,
            uint128 art
        ) = witch.auctions(VAULT_ID);
        assertEq(owner, auction.owner);
        assertEq(start, auction.start);
        assertEq(baseId, auction.baseId);
        assertEq(art, auction.art);
        assertEq(ink, auction.ink);

        (, , , uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);
    }
}

contract WitchV2WithAuction is WitchV2WithMetadata {
    using Mocks for *;

    bytes12 internal constant VAULT_ID_2 = "vault2";

    function setUp() public virtual override {
        super.setUp();

        cauldron.level.mock(VAULT_ID, -1);
        cauldron.give.mock(VAULT_ID, address(witch), vault);
        witch.auction(VAULT_ID);
    }

    function _stubVault(
        bytes12 vaultId,
        uint128 ink,
        uint128 art,
        int256 level
    ) internal {
        DataTypes.Vault memory v = DataTypes.Vault({
            owner: bob,
            seriesId: SERIES_ID,
            ilkId: ILK_ID
        });
        DataTypes.Balances memory b = DataTypes.Balances(art, ink);
        cauldron.vaults.mock(vaultId, v);
        cauldron.balances.mock(vaultId, b);
        cauldron.level.mock(vaultId, level);
        cauldron.give.mock(vaultId, address(witch), v);
    }

    function testCalcPayoutAfterAuction() public {
        // 100 * 0.5 * 0.714 = 35.7
        // (ink * proportion * initialOffer)
        assertEq(witch.calcPayout(VAULT_ID, 50_000e6), 35.7 ether);

        skip(5 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 300/3600) = 36.8916666667
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        assertEq(
            witch.calcPayout(VAULT_ID, 50_000e6),
            36.89166666666666665 ether
        );

        skip(25 minutes);
        // 100 * 0.5 * (0.714 + (1 - 0.714) * 1800/3600) = 42.85
        // (ink * proportion * (initialOffer + (1 - initialOffer) * timeElapsed)
        assertEq(witch.calcPayout(VAULT_ID, 50_000e6), 42.85 ether);

        // Right at auction end
        skip(30 minutes);
        // 100 * 0.5 = 50
        // (ink * proportion)
        assertEq(witch.calcPayout(VAULT_ID, 50_000e6), 50 ether);

        // After the auction ends the value is fixed
        skip(1 hours);
        assertEq(witch.calcPayout(VAULT_ID, 50_000e6), 50 ether);
    }

    function testAuctionAlreadyExists() public {
        vm.expectRevert("Vault already under auction");
        witch.auction(VAULT_ID);
    }

    function testCollateralLimits() public {
        // Given
        (, , , uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);

        _stubVault(VAULT_ID_2, 101 ether, 100_000e6, -1);

        // When
        witch.auction(VAULT_ID_2);

        // Then
        (, , , sum) = witch.limits(ILK_ID, BASE_ID);
        // Max is 100, but the position could be auctioned due to the soft limit
        // Next position will fail
        assertEq(sum, 100.5 ether);

        // Given
        bytes12 otherVaultId = "other vault";
        _stubVault(otherVaultId, 10 ether, 20_000e6, -1);

        // Expect
        vm.expectRevert("Collateral limit reached");

        // When
        witch.auction(otherVaultId);
    }

    function testDustLimit() public {
        // Half of this vault would be less than the min of 5k
        _stubVault(VAULT_ID_2, 5 ether, 9999e6, -1);

        WitchV2.Auction memory auction = witch.auction(VAULT_ID_2);

        assertEq(auction.owner, vault.owner);
        assertEq(auction.start, uint32(block.timestamp));
        assertEq(auction.baseId, series.baseId);
        // 100% of the vault was put for liquidation
        assertEq(auction.art, 9999e6);
        assertEq(auction.ink, 5 ether);
    }

    function testUpdateLimit() public {
        (, , , uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);

        vm.prank(ada);
        witch.setLimit(ILK_ID, BASE_ID, 1, 2, 3);

        (uint96 _max, uint24 _dust, uint8 _dec, uint128 _sum) = witch.limits(
            ILK_ID,
            BASE_ID
        );

        assertEq(_max, 1);
        assertEq(_dust, 2);
        assertEq(_dec, 3);
        // Sum is copied from old values
        assertEq(_sum, 50 ether);
    }

    function testCancelNonExistentAuction() public {
        vm.expectRevert("Vault not under auction");
        witch.cancel(VAULT_ID_2);
    }

    function testCancelUndercollateralisedAuction() public {
        vm.expectRevert("Undercollateralized");
        witch.cancel(VAULT_ID);
    }

    function testCancelAuction() public {
        (, , , uint128 sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 50 ether);

        cauldron.level.mock(VAULT_ID, 0);
        cauldron.give.mock(VAULT_ID, bob, vault);
        cauldron.give.verify(VAULT_ID, bob);

        vm.expectEmit(true, true, true, true);
        emit Cancelled(VAULT_ID);

        witch.cancel(VAULT_ID);

        // sum is reduced by the auction.ink
        (, , , sum) = witch.limits(ILK_ID, BASE_ID);
        assertEq(sum, 0);

        // Auction was deleted
        (
            address owner,
            uint32 start,
            bytes6 baseId,
            uint128 ink,
            uint128 art
        ) = witch.auctions(VAULT_ID);
        assertEq(owner, address(0));
        assertEq(start, 0);
        assertEq(baseId, "");
        assertEq(art, 0);
        assertEq(ink, 0);
    }
}

//   WithAuction

//     payBase -> WithPartialAuction
//      - "Vault not under auction"
//      - "Not enough bought"
//      - "Leaves dust"
//      - Storage changes
//      - Cauldron accounting
//      - Token transfers
//      - Bought
//      - Return values
//     payBaseAll -> ZeroState
//      - Pay over the vault debt
//      - Return vault
//      - Storage changes
//     payFYToken -> WithPartialAuction
//      - "Vault not under auction"
//      - "Not enough bought"
//      - Storage changes
//      - Cauldron accounting
//      - Token transfers/burns
//      - Bought
//      - Return values
//     payFYToken -> ZeroState
//      - Pay over the vault debt
//      - Return vault
//      - Storage changes
//     WithPartialAuction
//       payBaseFromPartial
//        - "Vault not under auction"
//        - "Not enough bought"
//        - "Leaves dust"
//        - Storage changes
//        - Cauldron accounting
//        - Token transfers
//        - Bought
//        - Return values
//       payBaseAllFromPartial
//        - Pay over the vault debt
//        - Return vault
//        - Storage changes
//       payFYTokenFromPartial
//        - "Vault not under auction"
//        - "Not enough bought"
//        - Storage changes
//        - Cauldron accounting
//        - Token transfers/burns
//        - Bought
//        - Return values
//       payFYTokenAllFromPartial
//        - Pay over the vault debt
//        - Return vault
//        - Storage changes

/* contract WitchAuctionTest is WitchTest {
    using Mocks for *;

    function setUp() public override {
        super.setUp();
    }

    function testUnknwonUserCanNotChangeLadle() public {
        vm.expectRevert("Access denied");
        witch.point("ladle", address(1));
    }

    function testCanChangeLadle() public {
        // Given
        assertEq(address(witch.ladle()), address(ladle));
        address anotherLadle = Mocks.mock("Ladle2");

        witch.grantRole(witch.point.selector, admin);

        // When
        vm.prank(admin);
        witch.point("ladle", anotherLadle);

        // Then
        assertEq(address(witch.ladle()), anotherLadle);
    }

    function testUnknwonUserCanNotSetIlk() public {
        vm.expectRevert("Access denied");
        witch.setIlk(ILK_ID, AUCTION_DURATION, 1e18 + 1, 1000000, 0, 6);
    }

    function testSetIlkWithMaxInitialProportionGt100() public {
        // Given
        witch.grantRole(witch.setIlk.selector, admin);

        // Expect
        vm.expectRevert("Only at or under 100%");

        // When
        vm.prank(admin);
        witch.setIlk(ILK_ID, AUCTION_DURATION, 1e18 + 1, 1000000, 0, 6);
    }

    function testSetIlkWithMaxInitialProportion() public {
        _setIlkWithMaxInitialProportion100(1e18); //100%
        _setIlkWithMaxInitialProportion100(1e18 - 1); //99.9999%
    }

    function _setIlkWithMaxInitialProportion100(uint64 _initialOffer) internal {
        // Given
        witch.grantRole(witch.setIlk.selector, admin);

        // When
        vm.prank(admin);
        witch.setIlk(ILK_ID, AUCTION_DURATION, _initialOffer, 1000000, 0, 6);

        // Then
        (uint32 duration, uint64 initialOffer) = witch.ilks(ILK_ID);
        assertEq(duration, AUCTION_DURATION);
        assertEq(initialOffer, _initialOffer);
        (uint96 line, uint24 dust, uint8 dec, uint128 sum) = witch.limits(ILK_ID);
        assertEq(line, 1000000);
        assertEq(dust, 0);
        assertEq(dec, 6);
        assertEq(sum, 0);
    }

    function testDoNotAllowToBuyFromVaultsNotBeingAuctioned() public {
        vm.expectRevert("Vault not under auction");
        witch.buy(VAULT_ID, 0, 0);

        vm.expectRevert("Vault not under auction");
        witch.payAll(VAULT_ID, 0);
    }

    function testDoNotAuctionCollateralisedVaults() public {
        _vaultIsCollateralised(VAULT_ID);

        vm.expectRevert("Not undercollateralized");
        witch.auction(VAULT_ID);
    }

    function testDoNotAuctionVaultIfLineExceeded() public {
        // Given
        witch.grantRole(witch.setIlk.selector, admin);
        vm.prank(admin);
        witch.setIlk(ILK_ID, 1, 2, 1, 0, 6);

        _vaultIsUndercollateralised(VAULT_ID);
        cauldron.vaults.mock(VAULT_ID, DataTypes.Vault(address(0xb0b), "series", ILK_ID));
        cauldron.balances.mock(VAULT_ID, DataTypes.Balances(3e6, 4e6));

        // Expect
        vm.expectRevert("Collateral limit reached");

        // When
        witch.auction(VAULT_ID);
    }

    function testAuctionsUndercollateralisedVaults() public {
        // Given
        witch.grantRole(witch.setIlk.selector, admin);
        vm.prank(admin);
        witch.setIlk(ILK_ID, AUCTION_DURATION, 0.5e18, 1000000, 0, 6);

        address owner = address(0xb0b);
        DataTypes.Vault memory vault = DataTypes.Vault(owner, "series", ILK_ID);
        DataTypes.Balances memory balances = DataTypes.Balances(3e18, 4e6);
        _stubVaultForAuction(VAULT_ID, vault, balances);
        _vaultIsUndercollateralised(VAULT_ID);

        // Expect
        vm.expectEmit(true, true, false, false);
        emit Auctioned(VAULT_ID, block.timestamp);

        // When
        witch.auction(VAULT_ID);

        // Then
        (address _owner, uint32 _start) = witch.auctions(VAULT_ID);
        (, , , uint128 _sum) = witch.limits(ILK_ID);
        assertEq(_owner, owner);
        assertEq(_start, block.timestamp);
        assertEq(_sum, balances.ink);
    }
}

contract WitchTestWithAuctionedVault is WitchTest {
    using Mocks for *;

    bytes6 internal constant BASE_ID = DAI;

    bytes6 internal constant SERIES_ID = "series";
    DataTypes.Series internal series =
        DataTypes.Series(IFYToken(address(0)), BASE_ID, uint32(block.timestamp + 30 days));

    bytes12 internal constant VAULT_A = "vaultA";
    address internal constant BOB = address(0xb0b);
    DataTypes.Vault internal vaultA = DataTypes.Vault(BOB, SERIES_ID, ILK_ID);
    DataTypes.Balances internal vaultABalances = DataTypes.Balances(3e18, 4e6);

    bytes12 internal constant VAULT_B = "vaultB";
    address internal constant COCO = address(0xc0c0);
    DataTypes.Vault internal vaultB = DataTypes.Vault(COCO, SERIES_ID, ILK_ID);
    DataTypes.Balances internal vaultBBalances = DataTypes.Balances(6e18, 8e6);

    address internal keeper;

    function setUp() public virtual override {
        super.setUp();

        keeper = utils.getNextUserAddress("Keeper");

        witch.grantRole(witch.setIlk.selector, admin);
        vm.prank(admin);
        witch.setIlk(ILK_ID, AUCTION_DURATION, 0.5e18, 1000000, 0, 6);

        _stubVaultForAuction(VAULT_A, vaultA, vaultABalances);
        _vaultIsUndercollateralised(VAULT_A);

        witch.auction(VAULT_A);
    }

    function _stubBuy(
        uint128 baseToRepayArt,
        uint128 debtFromBase,
        uint128 inkBought
    ) internal {
        cauldron.series.mock(SERIES_ID, series);
        cauldron.debtFromBase.mock(SERIES_ID, baseToRepayArt, debtFromBase);

        cauldron.slurp.mock(VAULT_A, inkBought, debtFromBase, vaultABalances);
        cauldron.give.mock(VAULT_A, BOB, vaultA);

        IJoin baseJoin = IJoin(Mocks.mock("BaseJoin"));
        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(BASE_ID, baseJoin);
        ladle.joins.mock(ILK_ID, ilkJoin);

        baseJoin.join.mock(keeper, baseToRepayArt, baseToRepayArt);
        ilkJoin.exit.mock(keeper, inkBought, inkBought);
    }

    function _stubBuy(uint128 baseToRepayArt, uint128 inkBought) internal {
        _stubBuy(baseToRepayArt, baseToRepayArt, inkBought);
    }
}

contract WitchAuctionedTest is WitchTestWithAuctionedVault {
    using Mocks for *;

    function setUp() public override {
        super.setUp();
    }

    function testVaultCanNotBeAuctionedTwice() public {
        vm.expectRevert("Vault already under auction");
        witch.auction(VAULT_A);
    }

    function testItCanAuctionOtherVaults() public {
        // Given
        _stubVaultForAuction(VAULT_B, vaultB, vaultBBalances);
        _vaultIsUndercollateralised(VAULT_B);

        // When
        witch.auction(VAULT_B);

        // Then
        (, , , uint128 _sum) = witch.limits(ILK_ID);
        assertEq(_sum, vaultABalances.ink + vaultBBalances.ink);
    }

    function testDonNotAuctionFurtherVaultsIfLineExceeded() public {
        // Given
        _stubVaultForAuction(VAULT_B, vaultB, vaultBBalances);
        _vaultIsUndercollateralised(VAULT_B);

        vm.prank(admin);
        witch.setIlk(ILK_ID, AUCTION_DURATION, 0.5e18, 4, 0, 6);

        // Expect
        vm.expectRevert("Collateral limit reached");

        // When
        witch.auction(VAULT_B);
    }

    function testDoesNotAllowBuyingUnderMinimumRequired() public {
        cauldron.series.mock(SERIES_ID, series);
        cauldron.debtFromBase.mock(SERIES_ID, 1e18, 1e18);

        vm.expectRevert("Not enough bought");
        witch.buy(VAULT_A, 1e18, 1e6);
    }

    function testCanBuyZeroCollateral() public {
        _stubBuy(0, 0);

        vm.expectEmit(true, true, false, false);
        emit Bought(VAULT_A, keeper, 0, 0);

        vm.prank(keeper);
        witch.buy(VAULT_A, 0, 0);
    }

    function testAllowsToBuyHalfOfCollateralAmountFromTheBeggining() public {
        uint128 baseToRepayArt = 3e18;
        uint128 inkToBuy = 2e6;
        // There's some rounding up on the calculated ink value, so an extra wei has to be added
        uint128 inkBought = inkToBuy + 1;

        _stubBuy(baseToRepayArt, inkBought);

        vm.expectEmit(true, true, false, false);
        emit Bought(VAULT_A, keeper, inkBought, baseToRepayArt);

        vm.prank(keeper);
        witch.buy(VAULT_A, baseToRepayArt, inkToBuy);
    }

    function testAllowsToBuyHalfOfCollateralAmountFromTheBegginingPayingAllDebt() public {
        uint128 baseToRepayArt = 3e18;
        uint128 inkToBuy = 2e6;
        // There's some rounding up on the calculated ink value, so an extra wei has to be added
        uint128 inkBought = inkToBuy + 1;

        _stubBuy(baseToRepayArt, inkBought);
        cauldron.debtToBase.mock(SERIES_ID, baseToRepayArt, baseToRepayArt);

        vm.expectEmit(true, true, false, false);
        emit Bought(VAULT_A, keeper, inkBought, baseToRepayArt);

        vm.prank(keeper);
        witch.payAll(VAULT_A, inkToBuy);
    }

    function testCanNotBuyMoreThanAuctionedPrice() public {
        uint128 baseToRepayArt = 3e18;
        uint128 inkToBuy = 2.1e6;

        cauldron.series.mock(SERIES_ID, series);
        cauldron.debtFromBase.mock(SERIES_ID, baseToRepayArt, baseToRepayArt);

        vm.expectRevert("Not enough bought");
        witch.buy(VAULT_A, baseToRepayArt, inkToBuy);
    }

    function testAuctionPriceIncreasesWithTime() public {
        uint128 baseToRepayArt = 3e18;
        uint128 inkToBuy = 3e6;
        // There's some rounding up on the calculated ink value, so an extra 3 weis have to be added
        uint128 inkBought = inkToBuy + 3;

        _stubBuy(baseToRepayArt, inkBought);

        // Can't buy that much collateral
        vm.expectRevert("Not enough bought");
        witch.buy(VAULT_A, baseToRepayArt, inkToBuy);

        // after 1/2 of AUCTION_DURATION the offered qty grows by 50%
        skip(AUCTION_DURATION / 2);

        vm.expectEmit(true, true, false, false);
        emit Bought(VAULT_A, keeper, inkBought, baseToRepayArt);

        vm.prank(keeper);
        witch.buy(VAULT_A, baseToRepayArt, inkToBuy);
    }

    function testCanNotBuyIfLeavingDust() public {
        uint128 baseToRepayArt = 2e18;
        uint128 inkToBuy = 1.3e6;

        cauldron.series.mock(SERIES_ID, series);
        cauldron.debtFromBase.mock(SERIES_ID, baseToRepayArt, baseToRepayArt);

        vm.prank(admin);
        witch.setIlk(ILK_ID, AUCTION_DURATION, 0.5e18, 1000000, 3, 6);

        vm.expectRevert("Leaves dust");
        witch.buy(VAULT_A, baseToRepayArt, inkToBuy);
    }

    function testAmountToRepayGrowsAfterMaturity() public {
        uint128 baseToRepayArt = vaultABalances.art + 100;
        uint128 inkToBuy = 2e6;
        // There's some rounding up on the calculated ink value, so an extra wei has to be added
        uint128 inkBought = inkToBuy + 1;
        uint128 debtFromBase = vaultABalances.art;

        _stubBuy(baseToRepayArt, debtFromBase, inkBought);

        vm.expectEmit(true, true, false, false);
        emit Bought(VAULT_A, keeper, inkBought, debtFromBase);

        vm.prank(keeper);
        witch.buy(VAULT_A, baseToRepayArt, inkToBuy);
    }

    function testAmountToRepayGrowsAfterMaturityPayAll() public {
        uint128 baseToRepayArt = vaultABalances.art + 100;
        uint128 inkToBuy = vaultABalances.ink / 2;
        uint128 inkBought = inkToBuy+1;

        cauldron.series.mock(SERIES_ID, series);
        cauldron.debtToBase.mock(SERIES_ID, vaultABalances.art, baseToRepayArt);

        cauldron.slurp.mock(VAULT_A, inkBought, vaultABalances.art, vaultABalances);
        cauldron.give.mock(VAULT_A, BOB, vaultA);

        IJoin baseJoin = IJoin(Mocks.mock("BaseJoin"));
        IJoin ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(BASE_ID, baseJoin);
        ladle.joins.mock(ILK_ID, ilkJoin);

        baseJoin.join.mock(keeper, baseToRepayArt, baseToRepayArt);
        ilkJoin.exit.mock(keeper, inkBought, inkBought);

        vm.expectEmit(true, true, false, false);
        emit Bought(VAULT_A, keeper, inkBought, baseToRepayArt);

        vm.prank(keeper);
        witch.payAll(VAULT_A, inkToBuy);
    }
}

contract WitchAuctionExpiredTest is WitchTestWithAuctionedVault {
    using Mocks for *;

    function setUp() public override {
        super.setUp();

        skip(AUCTION_DURATION);
    }

    function testAllowsToBuyAllCollateralAfterAuctionExpires() public {
        uint128 baseToRepayArt = vaultABalances.art;
        uint128 inkToBuy = vaultABalances.ink;

        _stubBuy(baseToRepayArt, inkToBuy);
        cauldron.debtToBase.mock(SERIES_ID, baseToRepayArt, baseToRepayArt);

        vm.expectEmit(true, true, false, false);
        emit Bought(VAULT_A, keeper, inkToBuy, baseToRepayArt);

        vm.prank(keeper);
        witch.payAll(VAULT_A, inkToBuy);
    }
} */
