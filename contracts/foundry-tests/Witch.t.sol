// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "forge-std/Test.sol";
import "./utils/TestConstants.sol";
import "./utils/Utilities.sol";
import "./utils/Mocks.sol";

// import "@yield-protocol/vault-interfaces/src/ILadle.sol";
// import "@yield-protocol/vault-interfaces/src/ICauldron.sol";

import "../Witch.sol";

contract WithWitch is Test, TestConstants {
    bytes12 internal constant VAULT_ID = "vault";

    Utilities internal utils;

    address internal admin;

    ICauldron internal cauldron;
    ILadle internal ladle;

    Witch internal sut;

    function setUp() public virtual {
        utils = new Utilities();

        admin = utils.getNextUserAddress();
        cauldron = ICauldron(Mocks.mock("Cauldron"));
        ladle = ILadle(Mocks.mock("Ladle"));

        sut = new Witch(cauldron, ladle);
    }

    event Auctioned(bytes12 indexed vaultId, uint256 indexed start);
}

contract WitchAuctionTest is WithWitch {
    using Mocks for *;

    function setUp() public override {
        super.setUp();
    }

    function testUnknwonUserCanNotChangeLadle() public {
        vm.expectRevert("Access denied");
        sut.point("ladle", address(1));
    }

    function testCanChangeLadle() public {
        // Given
        assertEq(address(sut.ladle()), address(ladle));
        address anotherLadle = Mocks.mock("Ladle2");

        sut.grantRole(sut.point.selector, admin);

        // When
        vm.prank(admin);
        sut.point("ladle", anotherLadle);

        // Then
        assertEq(address(sut.ladle()), anotherLadle);
    }

    function testUnknwonUserCanNotSetIlk() public {
        vm.expectRevert("Access denied");
        sut.setIlk(USDC, 1 hours, 1e18 + 1, 1000000, 0, 6);
    }

    function testSetIlkWithMaxInitialProportionGt100() public {
        // Given
        sut.grantRole(sut.setIlk.selector, admin);

        // Expect
        vm.expectRevert("Only at or under 100%");

        // When
        vm.prank(admin);
        sut.setIlk(USDC, 1 hours, 1e18 + 1, 1000000, 0, 6);
    }

    function testSetIlkWithMaxInitialProportion() public {
        _setIlkWithMaxInitialProportion100(1e18); //100%
        _setIlkWithMaxInitialProportion100(1e18 - 1); //99.9999%
    }

    function _setIlkWithMaxInitialProportion100(uint64 _initialOffer) internal {
        // Given
        sut.grantRole(sut.setIlk.selector, admin);

        // When
        vm.prank(admin);
        sut.setIlk(USDC, 1 hours, _initialOffer, 1000000, 0, 6);

        // Then
        (uint32 duration, uint64 initialOffer) = sut.ilks(USDC);
        assertEq(duration, 1 hours);
        assertEq(initialOffer, _initialOffer);
        (uint96 line, uint24 dust, uint8 dec, uint128 sum) = sut.limits(USDC);
        assertEq(line, 1000000);
        assertEq(dust, 0);
        assertEq(dec, 6);
        assertEq(sum, 0);
    }

    function testDoNotAllowToBuyFromVaultsNotBeingAuctioned() public {
        vm.expectRevert("Vault not under auction");
        sut.buy(VAULT_ID, 0, 0);

        vm.expectRevert("Vault not under auction");
        sut.payAll(VAULT_ID, 0);
    }

    function testDoNotAuctionCollateralisedVaults() public {
        _vaultIsCollateralised(VAULT_ID);

        vm.expectRevert("Not undercollateralized");
        sut.auction(VAULT_ID);
    }

    function testDoNotAuctionVaultIfLineExceeded() public {
        // Given
        sut.grantRole(sut.setIlk.selector, admin);
        vm.prank(admin);
        sut.setIlk(USDC, 1, 2, 1, 0, 6);

        _vaultIsUndercollateralised(VAULT_ID);
        cauldron.vaults.mock(VAULT_ID, DataTypes.Vault(address(0xb0b), "series", USDC));
        cauldron.balances.mock(VAULT_ID, DataTypes.Balances(3e6, 4e6));

        // Expect
        vm.expectRevert("Collateral limit reached");

        // When
        sut.auction(VAULT_ID);
    }

    function testAuctionsUndercollateralisedVaults() public {
        // Given
        sut.grantRole(sut.setIlk.selector, admin);
        vm.prank(admin);
        sut.setIlk(USDC, 1 hours, 0.5e18, 1000000, 0, 6);

        _vaultIsUndercollateralised(VAULT_ID);

        address owner = address(0xb0b);
        DataTypes.Vault memory vault = DataTypes.Vault(owner, "series", USDC);
        cauldron.vaults.mock(VAULT_ID, vault);
        DataTypes.Balances memory balances = DataTypes.Balances(3e6, 4e6);
        cauldron.balances.mock(VAULT_ID, balances);
        cauldron.give.mock(VAULT_ID, address(sut), vault);

        // Expect
        cauldron.give.verify(VAULT_ID, address(sut));
        vm.expectEmit(true, true, false, false);
        emit Auctioned(VAULT_ID, block.timestamp);

        // When
        sut.auction(VAULT_ID);

        // Then
        (address _owner, uint32 _start) = sut.auctions(VAULT_ID);
        (, , , uint128 _sum) = sut.limits(USDC);
        assertEq(_owner, owner);
        assertEq(_start, block.timestamp);
        assertEq(_sum, balances.ink);
    }

    function _vaultIsCollateralised(bytes12 vaultId) internal {
        cauldron.level.mock(vaultId, 0); // >= 0 means vault is collateralised
    }

    function _vaultIsUndercollateralised(bytes12 vaultId) internal {
        cauldron.level.mock(vaultId, -1); // < 0 means vault is undercollateralised
    }
}

