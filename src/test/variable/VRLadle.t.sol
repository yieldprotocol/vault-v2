// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";
import "../../mocks/ERC20Mock.sol";
using Cast for uint256;
using Cast for int128;

contract VRLadleAdminTests is ZeroState {

    // Test that the storage is initialized
    function testStorageInitialized() public {
        assertTrue(ladle.initialized());
    }

    // Test that the storage can't be initialized again
    function testInitializeRevertsIfInitialized() public {
        ladle.grantRole(ladle.initialize.selector, address(this));
        
        vm.expectRevert("Already initialized");
        ladle.initialize(address(this));
    }

    // Test that only authorized addresses can upgrade
    function testUpgradeToRevertsIfNotAuthed() public {
        vm.expectRevert("Access denied");
        ladle.upgradeTo(address(0));
    }

    // Test that the upgrade works
    function testUpgradeTo() public {
        VRLadle ladleV2 = new VRLadle(
            IVRCauldron(address(cauldron)),
            IRouter(address(0)),
            IWETH9(address(weth))
        );

        ladle.grantRole(0x3659cfe6, address(this)); // upgradeTo(address)
        ladle.upgradeTo(address(ladleV2));

        assertEq(address(ladle.router()), address(0));
        assertTrue(ladle.hasRole(ladle.ROOT(), address(this)));
        assertTrue(ladle.initialized());
    }

    // @notice Test ability to set borrowing fee
    function testSetBorrowingFee() public {
        console.log("admin can set borrowing fee");
        ladle.setFee(1000);
        assertEq(ladle.borrowingFee(), 1000);
    }
}

contract VRLadleJoinAdminTests is ZeroState {
    // @notice Test not able to add join before adding ilk
    function testNoAddJoinWithoutIlk() public {
        console.log("cannot add join without asset being added first");
        vm.expectRevert("Asset not found");
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
    }

    // @notice Test not able to add join with a mismatched ilk
    function testAddJoinMismatch() public {
        console.log("cannot add join with mismatched asset");
        cauldron.addAsset(usdcId, address(usdc));
        vm.expectRevert("Mismatched asset and join");
        ladle.addJoin(usdcId, IJoin(address(daiJoin)));
    }

    // @notice Test ability to add join
    function testAddJoin() public {
        console.log("can add join for an asset which is present");
        cauldron.addAsset(usdcId, address(usdc));
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
        assertEq(address(ladle.joins(usdcId)), address(usdcJoin));
    }

    // @notice Test the same join for a second ilk of the same asset
    function testAddJoinSameAsset() public {
        console.log("can add the same join for different asset");
        cauldron.addAsset(usdcId, address(usdc));
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
        cauldron.addAsset(otherIlkId, address(usdc));
        ladle.addJoin(otherIlkId, IJoin(address(usdcJoin)));
        assertEq(address(ladle.joins(usdcId)), address(usdcJoin));
        assertEq(address(ladle.joins(otherIlkId)), address(usdcJoin));
    }
}

contract VaultTests is VaultBuiltState {
    function testBuildVault() public {
        console.log("can build a vault");
        (bytes12 vaultId_, ) = ladle.build(baseId, usdcId, 123);
        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(
            vaultId_
        );
        assertEq(baseId_, baseId);
        assertEq(ilkId_, usdcId);
        assertEq(owner, address(this));
    }

    function testZeroIlkId() public {
        console.log("cannot build a vault with zero ilk id");
        vm.expectRevert("Ilk id is zero");
        ladle.build(baseId, bytes6(0), 123);
    }

    function testTweakOnlyOwner() public {
        console.log("cannot tweak a vault with a different owner");
        vm.expectRevert("Only vault owner");
        vm.prank(admin);
        ladle.tweak(vaultId, baseId, usdcId);
    }

    function testDestroyVault() public {
        console.log("can destroy a vault");
        vm.expectEmit(true, false, false, false);
        emit VaultDestroyed(vaultId);
        ladle.destroy(vaultId);
    }

    function testChangeVault() public {
        console.log("can change a vault");
        vm.expectEmit(true, true, true, false);
        emit VaultTweaked(vaultId, baseId, daiId);
        ladle.tweak(vaultId, baseId, daiId);

        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(
            vaultId
        );
        assertEq(baseId_, baseId);
        assertEq(ilkId_, daiId);
        assertEq(owner, address(this));
    }

    function testGiveVault() public {
        console.log("can give a vault");
        vm.expectEmit(true, true, false, false);
        emit VaultGiven(vaultId, admin);
        ladle.give(vaultId, admin);

        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(
            vaultId
        );
        assertEq(baseId_, baseId);
        assertEq(ilkId_, usdcId);
        assertEq(owner, admin);
    }

    function testOtherCantChangeOwnerOfVault() public {
        console.log("cannot change owner of a vault with a different owner");
        vm.expectRevert("Only vault owner");
        vm.prank(admin);
        ladle.give(vaultId, admin);
    }

    function testOnlyOwnerCouldMove() public {
        console.log("cannot move a vault with a different owner");
        vm.prank(admin);
        vm.expectRevert("Only origin vault owner");
        ladle.stir(vaultId, otherVaultId, 1, 1);
    }

    function testOnlyDestinationVaultOwner() public {
        vm.prank(admin);
        vm.expectRevert("Only destination vault owner");
        ladle.stir(vaultId, otherVaultId, 0, 1);
    }
}

contract PourTests is VaultBuiltState {
    function setUp() public override {
        super.setUp();
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vaultId);
        IERC20 token = IERC20(cauldron.assets(ilkId));
        deal(address(token), address(this), INK);
        token.approve(address(ladle.joins(ilkId)), INK);
    }

    function testOnlyOwnerCanPour() public {
        console.log("other users can't pour into a vault");
        vm.expectRevert("Only vault owner");
        vm.prank(admin);
        ladle.pour(vaultId, address(this), 1000, 1000);
    }

    function testPourToPostCollateral() public {
        console.log("can pour collateral into a vault");
        ladle.pour(vaultId, address(this), INK.i128(), 0);
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }

    function testPourToPostAndBorrow() public {
        console.log("can pour collateral into a vault and borrow");
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vaultId);

        ladle.pour(vaultId, address(this), INK.i128(), ART.i128());
        assertEq(IERC20(cauldron.assets(baseId)).balanceOf(address(this)), ART);

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }

    function testPourToPostAndBorrowToOther() public {
        console.log(
            "can pour collateral into a vault and send the borrowed amount to other address"
        );
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vaultId);

        ladle.pour(vaultId, admin, INK.i128(), ART.i128());
        assertEq(IERC20(cauldron.assets(baseId)).balanceOf(admin), ART);

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }
}

contract PouredStateTests is CauldronPouredState {
    function testPourToWithdraw() public {
        console.log("can pour to withdraw");
        (, , bytes6 ilkId) = cauldron.vaults(vaultId);

        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(address(this)), 0);
        vm.expectEmit(true, true, true, true);
        emit VaultPoured(vaultId, baseId, ilkId, -(INK).i128(), 0);
        ladle.pour(vaultId, address(this), -(INK).i128(), 0);
        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(address(this)), INK);

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testPourToWithdrawToOther() public {
        console.log("can pour to withdraw to other address");
        (, , bytes6 ilkId) = cauldron.vaults(vaultId);

        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(address(this)), 0);
        vm.expectEmit(true, true, true, true);
        emit VaultPoured(vaultId, baseId, ilkId, -(INK).i128(), 0);
        ladle.pour(vaultId, admin, -(INK).i128(), 0);
        assertEq(IERC20(cauldron.assets(ilkId)).balanceOf(admin), INK);

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testCannotBorrowUnderLimit() public {
        console.log("cannot borrow under the min debt");
        vm.expectRevert("Min debt not reached");
        ladle.pour(vaultId, address(this), 0, 1);
    }

    function testPourToBorrowBase() public {
        console.log("can pour to borrow base");
        ladle.pour(vaultId, address(this), 0, (ART).i128());

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }

    function testFeeChargeOnBorrow() public {
        console.log("fee can be charged on borrow");
        ladle.setFee(FEE);
        ladle.pour(vaultId, address(this), 0, (ART).i128());

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, ART + FEE);
    }

    function testMoveDebt() public {
        console.log("can move debt from one vault to another");
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (address owner, , bytes6 ilkId) = cauldron.vaults(vaultId);
        deal(cauldron.assets(ilkId), owner, INK);
        IERC20(cauldron.assets(ilkId)).approve(
            address(ladle.joins(ilkId)),
            INK
        );
        ladle.pour(otherVaultId, msg.sender, (INK).i128(), 0);
        ladle.pour(vaultId, address(this), 0, (ART).i128());

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, 0, art);
        ladle.stir(vaultId, otherVaultId, 0, art);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }

    function testMoveCollateral() public {
        console.log("can move collateral from one vault to another");
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);

        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, ink, 0);
        ladle.stir(vaultId, otherVaultId, ink, 0);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }

    function testMoveDebtAndCollateral() public {
        console.log("can move debt and collateral from one vault to another");
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        ladle.pour(vaultId, address(this), 0, (ART).i128());
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);

        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, ink, art);
        ladle.stir(vaultId, otherVaultId, ink, art);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }

    function testMoveCollateralInABatch() public {
        console.log("can move collateral from one vault to another in a batch");
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(
            VRLadle.stir.selector,
            vaultId,
            otherVaultId,
            ink,
            0
        );

        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, ink, 0);
        ladle.batch(calls);

        (art, ink) = cauldron.balances(vaultId);
        assertEq(ink, 0);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }

    function testMoveDebtInABatch() public {
        console.log("can move debt from one vault to another in a batch");
        (bytes12 otherVaultId, ) = ladle.build(baseId, usdcId, 123);
        (address owner, , bytes6 ilkId) = cauldron.vaults(vaultId);
        deal(cauldron.assets(ilkId), owner, INK);
        IERC20(cauldron.assets(ilkId)).approve(
            address(ladle.joins(ilkId)),
            INK
        );
        ladle.pour(otherVaultId, msg.sender, (INK).i128(), 0);
        ladle.pour(vaultId, address(this), 0, (ART).i128());

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(
            VRLadle.stir.selector,
            vaultId,
            otherVaultId,
            0,
            ART
        );

        vm.expectEmit(true, true, true, true);
        emit VaultStirred(vaultId, otherVaultId, 0, uint128(ART));
        ladle.batch(calls);

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);

        (art, ink) = cauldron.balances(otherVaultId);
        assertEq(ink, INK);
        assertEq(art, ART);
    }
}

contract BorrowedStateTests is BorrowedState {
    IERC20 token;

    function setUp() public override {
        super.setUp();
        (, bytes6 baseId, ) = cauldron.vaults(vaultId);
        token = IERC20(cauldron.assets(baseId));
    }

    function testRepayDebt() public {
        console.log("can repay debt by pouring");
        token.approve(address(ladle.joins(baseId)), ART);
        ladle.pour(vaultId, address(this), 0, -(ART.i128()));

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testRepayDebtWithTransfer() public {
        console.log("can repay debt by transferring before pouring");
        token.transfer(address(ladle.joins(baseId)), ART);
        ladle.pour(vaultId, admin, 0, -(ART).i128());

        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testCantRepayMoreThanDebt() public {
        console.log("cannot repay more than debt");
        token.approve(address(ladle.joins(baseId)), ART + 10);
        vm.expectRevert("Result below zero");
        ladle.pour(vaultId, admin, 0, -(ART + 10).i128());
    }

    function testBorrowWhileUnderGlobalDebtLimit() public {
        console.log("can borrow while under global debt limit");
        ladle.pour(vaultId, address(this), 0, (ART).i128());
        (uint128 art, uint128 ink) = cauldron.balances(vaultId);
        assertEq(ink, INK);
        assertEq(art, ART * 2);
    }

    function testCantBorrowOverGlobalDebtLimit() public {
        console.log("cannot borrow over global debt limit");
        vm.expectRevert("Max debt exceeded");
        ladle.pour(vaultId, address(this), 0, (ART * 20 * 1e6).i128());
    }
}

contract PermitTests is CompleteSetup {
    struct Permit {
        address owner;
        address spender;
        uint256 value;
    }

    function getDaiPermitDigest(
        bytes memory name,
        address contractAddress,
        uint256 chainId,
        Permit memory permit,
        uint nonce,
        uint deadline,
        bool allowed
    ) internal view returns (bytes32) {
        bytes32 DOMAIN_SEPARATOR = getDomainSeparator(
            name,
            contractAddress,
            chainId
        );
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)"
                            ),
                            permit.owner,
                            permit.spender,
                            nonce,
                            deadline,
                            allowed
                        )
                    )
                )
            );
    }

    function getPermitDigest(bytes memory name, address contractAddress, uint256 chainId, Permit memory permit, uint nonce, uint deadline) internal pure returns (bytes32) {
        bytes32 DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(ERC20Permit(contractAddress).version())),
                chainId,
                contractAddress
            )
        );
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            permit.owner,
                            permit.spender,
                            permit.value,
                            nonce,
                            deadline
                        )
                    )
                )
            );
    }

    function getDomainSeparator(
        bytes memory name,
        address contractAddress,
        uint256 chainId
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        (
                            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                        )
                    ),
                    keccak256(bytes(IERC20Metadata(contractAddress).name())),
                    keccak256(("1")),
                    chainId,
                    contractAddress
                )
            );
    }

    function testCanUseLadleToExecutePermit() public {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        bytes32 permitDigest = getDaiPermitDigest(
            abi.encode(keccak256(bytes(IERC20Metadata(address(dai)).name()))), //name
            address(dai), //contractAddress
            chainId, //chainId
            Permit(
                user, //owner
                address(ladle.joins(daiId)), //spender
                100
            ), //value
            0, //nonce
            block.timestamp, //deadline
            true
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("user"))),
            permitDigest
        );
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit Approval(user, address(ladle.joins(daiId)), type(uint256).max);
        ladle.forwardDaiPermit(
            DaiAbstract(address(dai)),
            address(ladle.joins(daiId)),
            0,
            block.timestamp,
            true,
            v,
            r,
            s
        );
    }

    function testCantUseLadleToExecutePermitOnUnknownToken() public {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        bytes32 permitDigest = getPermitDigest(
            abi.encode(
                keccak256(bytes(IERC20Metadata(address(otherERC20)).name()))
            ), //name
            address(otherERC20), //contractAddress
            chainId, //chainId
            Permit(
                user, //owner
                address(ladle.joins(daiId)), //spender
                100
            ), //value
            0, //nonce
            block.timestamp //deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("user"))),
            permitDigest
        );
        vm.startPrank(user);
        vm.expectRevert("Unknown token");
        ladle.forwardPermit(
            otherERC20,
            address(0),
            0,
            block.timestamp,
            v,
            r,
            s
        );
    }
}

contract RouteAndIntegrationTests is CompleteSetup {
    function testTokenAdditionAndRemoval() public {
        console.log("can add and remove tokens");
        vm.expectEmit(true, true, true, true);
        emit TokenAdded(address(usdc), true);
        ladle.addToken(address(usdc), true);
        assert(ladle.tokens(address(usdc)));

        vm.expectEmit(true, true, true, true);
        emit TokenAdded(address(usdc), false);
        ladle.addToken(address(usdc), false);
        assert(!ladle.tokens(address(usdc)));
    }

    function testIntegrationAdditionAndRemoval() public {
        console.log("can add and remove integrations");
        vm.expectEmit(true, true, true, true);
        emit IntegrationAdded(address(usdc), true);
        ladle.addIntegration(address(usdc), true);
        assert(ladle.integrations(address(usdc)));

        vm.expectEmit(true, true, true, true);
        emit IntegrationAdded(address(usdc), false);
        ladle.addIntegration(address(usdc), false);
        assert(!ladle.integrations(address(usdc)));
    }

    function testOnlyCauldronCanUseRouter() public {
        console.log('router can be called only by cauldron');
        IRouter router = ladle.router();
        vm.expectRevert("Only owner");
        router.route(address(cauldron), "0x00000000");
    }
}

contract TokensAndIntegrationTests is WithTokensAndIntegrationState {
    function testCantRouteToEOA() public {
        console.log("can't route to an EOA");
        vm.expectRevert("Target is not a contract");
        ladle.route(user, "0x00000000");
    }

    function testUnknownToken() public {
        console.log("can't use transfer on a token not added to ladle");
        vm.expectRevert("Unknown token");
        ladle.transfer(IERC20(makeAddr("0x12")), user, uint128(WAD));
    }

    function testTransferTokenThroughLadle() public {
        console.log("can transfer token through ladle");
        deal(address(usdc), address(this), WAD);
        usdc.approve(address(ladle), WAD);
        ladle.transfer(usdc, admin, uint128(WAD));
    }

    function testFunctionCallOnIntegration() public {
        console.log("can call function on integration");
        vm.expectEmit(true, true, true, true);
        emit Approval(address(ladle.router()), address(this), WAD);
        ladle.route(
            address(dai),
            abi.encodeWithSelector(IERC20.approve.selector, address(this), WAD)
        );
    }

    function testUnknownIntegrationCantBeCalled() public {
        console.log("can't call function on unknown integration");
        vm.expectRevert("Unknown integration");
        ladle.route(
            address(usdc),
            abi.encodeWithSelector(IERC20.approve.selector, address(this), WAD)
        );
    }

    function testAuthorizationStripping() public {
        console.log("can't call function on integration without authorization");
        vm.expectRevert("Access denied");
        ladle.route(
            address(restrictedERC20Mock),
            abi.encodeWithSelector(
                RestrictedERC20Mock.mint.selector,
                address(this),
                WAD
            )
        );
    }
}

contract ETHTests is ETHVaultBuiltState {
    function testCanTransferETHThenPour() public {
        console.log("can transfer eth and then pour");
        ladle.wrapEther{value: INK}(address(ladle.joins(wethId)));
        vm.expectEmit(true, true, true, true);
        emit VaultPoured(ethVaultId, baseId, wethId, INK.i128(), 0);
        ladle.pour(ethVaultId, address(this), INK.i128(), 0);

        assertEq(weth.balanceOf(address(ladle.joins(wethId))), INK);
        (uint128 art, uint128 ink) = cauldron.balances(ethVaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }

    function testPourWithoutSendingETHReverts() public {
        console.log("pour without sending eth reverts");
        weth.approve(address(wethJoin), 0);
        vm.expectRevert("ERC20: Insufficient approval");
        ladle.pour(ethVaultId, address(this), INK.i128(), 0);
    }

    function testCanTransferETHAndPourInBatch() public {
        console.log("can transfer eth and pour in batch");
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            VRLadle.wrapEther.selector,
            address(ladle.joins(wethId))
        );
        calls[1] = abi.encodeWithSelector(
            VRLadle.pour.selector,
            ethVaultId,
            address(this),
            INK.i128(),
            0
        );

        vm.expectEmit(true, true, true, true);
        emit VaultPoured(ethVaultId, baseId, wethId, INK.i128(), 0);
        ladle.batch{value: INK}(calls);

        assertEq(weth.balanceOf(address(ladle.joins(wethId))), INK);
        (uint128 art, uint128 ink) = cauldron.balances(ethVaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }

    function testReceiveETHFromOnlyWETH() public {
        console.log("can't receive eth from non-weth");
        (bool sent, bytes memory data) = address(ladle).call{value: INK}("");
        assertTrue(!sent);
    }
}

contract ETHVaultPouredStateTest is ETHVaultPouredState {
    function testPourToWithdraw() public {
        console.log("can pour to withdraw");
        ladle.pour(ethVaultId, address(this), -INK.i128(), 0);

        assertEq(weth.balanceOf(address(ladle.joins(wethId))), 0);
        assertEq(weth.balanceOf(address(this)), INK);
        (uint128 art, uint128 ink) = cauldron.balances(ethVaultId);
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testWithdrawAndUnwrap() public {
        console.log("can withdraw and unwrap in a batch");
        uint initialBalance = address(this).balance;
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            VRLadle.pour.selector,
            ethVaultId,
            address(ladle),
            -INK.i128(),
            0
        );
        calls[1] = abi.encodeWithSelector(
            VRLadle.unwrapEther.selector,
            address(this)
        );

        ladle.batch(calls);

        assertEq(weth.balanceOf(address(ladle.joins(wethId))), 0);
        assertEq(weth.balanceOf(address(this)), 0);
        (uint128 art, uint128 ink) = cauldron.balances(ethVaultId);
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(INK, address(this).balance - initialBalance);
    }

    function testRepayETH() public {
        console.log("can repay eth");
        ladle.pour(ethVaultId, address(this), 0, (ART * 1000).i128());
        uint128 debtToBase = cauldron.debtToBase(baseId, uint128(ART * 1000));
        deal(address(base), address(this), debtToBase);
        IERC20(address(base)).approve(address(ladle.joins(baseId)), debtToBase);
        ladle.repay(ethVaultId, address(this), address(this), 0);
        (uint128 art, uint128 ink) = cauldron.balances(ethVaultId);
        assertEq(ink, INK);
        assertEq(art, 0);
    }
}

contract BatchTests is CompleteSetup {
    function testBuildTweakGive() public {
        console.log("can build tweak and give in a batch");
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(
            VRLadle.build.selector,
            baseId,
            usdcId,
            9
        );
        calls[1] = abi.encodeWithSelector(
            VRLadle.tweak.selector,
            bytes12(0),
            baseId,
            daiId
        );
        calls[2] = abi.encodeWithSelector(
            VRLadle.give.selector,
            bytes12(0),
            admin
        );

        ladle.batch(calls);

        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(
            bytes12(
                keccak256(
                    abi.encodePacked(address(this), block.timestamp, uint8(10))
                )
            )
        );
        assertEq(baseId_, baseId);
        assertEq(ilkId_, daiId);
        assertEq(owner, admin);
    }

    function testBuildAndGiveTwice() public {
        console.log("can build and give twice in a batch");
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSelector(
            VRLadle.build.selector,
            baseId,
            usdcId,
            9
        );
        calls[1] = abi.encodeWithSelector(
            VRLadle.give.selector,
            bytes12(0),
            admin
        );
        calls[2] = abi.encodeWithSelector(
            VRLadle.build.selector,
            baseId,
            usdcId,
            9
        );
        calls[3] = abi.encodeWithSelector(
            VRLadle.give.selector,
            bytes12(0),
            admin
        );

        ladle.batch(calls);

        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(
            bytes12(
                keccak256(
                    abi.encodePacked(address(this), block.timestamp, uint8(10))
                )
            )
        );
        assertEq(baseId_, baseId);
        assertEq(ilkId_, usdcId);
        assertEq(owner, admin);

        (owner, baseId_, ilkId_) = cauldron.vaults(
            bytes12(
                keccak256(
                    abi.encodePacked(address(this), block.timestamp, uint8(11))
                )
            )
        );
        assertEq(baseId_, baseId);
        assertEq(ilkId_, usdcId);
        assertEq(owner, admin);
    }

    function testBuildAndDestroyVault() public {
        console.log("can build and destroy vault in a batch");
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            VRLadle.build.selector,
            baseId,
            usdcId,
            9
        );
        calls[1] = abi.encodeWithSelector(VRLadle.destroy.selector, bytes12(0));

        ladle.batch(calls);

        (address owner, bytes6 baseId_, bytes6 ilkId_) = cauldron.vaults(
            bytes12(
                keccak256(
                    abi.encodePacked(address(this), block.timestamp, uint8(10))
                )
            )
        );
        assertEq(baseId_, bytes6(0));
        assertEq(ilkId_, bytes6(0));
        assertEq(owner, address(0));
    }

    function testCantTweakAfterGive() public {
        console.log("can't tweak after give");
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(
            VRLadle.build.selector,
            baseId,
            usdcId,
            9
        );
        calls[1] = abi.encodeWithSelector(
            VRLadle.give.selector,
            bytes12(0),
            admin
        );
        calls[2] = abi.encodeWithSelector(
            VRLadle.tweak.selector,
            bytes12(0),
            baseId,
            daiId
        );

        vm.expectRevert("Only vault owner");
        ladle.batch(calls);
    }
}
