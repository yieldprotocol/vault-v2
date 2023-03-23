// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./FixtureStates.sol";

contract VYTokenTest is VYTokenZeroState {

    // Test that the storage is initialized
    function testStorageInitialized() public {
        assertTrue(vyToken.initialized());
    }

    // Test that the storage can't be initialized again
    function testInitializeRevertsIfInitialized() public {
        vyToken.grantRole(VYToken.initialize.selector, address(this));
        
        vm.expectRevert("Already initialized");
        vyToken.initialize(address(this));
    }

    // Test that only authorized addresses can upgrade
    function testUpgradeToRevertsIfNotAuthed() public {
        vm.expectRevert("Access denied");
        vyToken.upgradeTo(address(0));
    }

    // Test that the upgrade works
    function testUpgradeTo() public {
        VYToken vyTokenV2 = new VYToken(0x303100000000, IOracle(address(1)), baseJoin, base.name(), base.symbol());

        vyToken.grantRole(0x3659cfe6, address(this)); // upgradeTo(address)
        vyToken.upgradeTo(address(vyTokenV2));

        assertEq(address(vyToken.oracle()), address(1));
        assertTrue(vyToken.hasRole(vyToken.ROOT(), address(this)));
        assertTrue(vyToken.initialized());
    }

    function testMintWithUnderlying() public {
        console.log("can mint with underlying");
        track("userTokenBalance", vyToken.balanceOf(address(this)));

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );

        vyToken.mint(address(this), unit);

        assertTrackPlusEq(
            "userTokenBalance",
            unit,
            vyToken.balanceOf(address(this))
        );
    }

    function testDepositToMint() public {
        console.log("can deposit to mint");
        track("userTokenBalance", vyToken.balanceOf(address(this)));
        track(
            "userUnderlyingBalance",
            IERC20(vyToken.underlying()).balanceOf(address(this))
        );

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );

        vyToken.deposit(address(this), unit);

        assertTrackPlusEq(
            "userTokenBalance",
            unit,
            vyToken.balanceOf(address(this))
        );
        assertTrackMinusEq(
            "userUnderlyingBalance",
            unit,
            IERC20(vyToken.underlying()).balanceOf(address(this))
        );
    }

    function testConvertToPrincipal() public {
        console.log("can convert amount of underlying to principal");
        assertEq(vyToken.convertToPrincipal(unit), unit);
    }

    function testConvertToUnderlying() public {
        console.log("can convert amount of principal to underlying");
        assertEq(vyToken.convertToUnderlying(unit), unit);
    }

    function testPreviewRedeem() public {
        console.log("can preview the amount of underlying redeemed");
        assertEq(vyToken.previewRedeem(unit), unit);
    }

    function testPreviewWithdraw() public {
        console.log("can preview the amount of principal withdrawn");
        assertEq(vyToken.previewWithdraw(unit), unit);
    }

    function testWithdraw() public {
        console.log("can withdraw principal");
        track("userTokenBalance", vyToken.balanceOf(address(this)));
        track(
            "userUnderlyingBalance",
            IERC20(vyToken.underlying()).balanceOf(address(this))
        );

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );

        vyToken.mint(address(this), unit);

        vyToken.withdraw(unit, address(this), address(this));
        assertTrackPlusEq(
            "userTokenBalance",
            0,
            vyToken.balanceOf(address(this))
        );

        assertEq(unit, IERC20(vyToken.underlying()).balanceOf(address(this)));
    }

    function testRedeem() public {
        console.log("can redeem underlying");
        track("userTokenBalance", vyToken.balanceOf(address(this)));
        track(
            "userUnderlyingBalance",
            IERC20(vyToken.underlying()).balanceOf(address(this))
        );

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );
        vyToken.mint(address(this), unit);

        vyToken.redeem(unit, address(this), address(this));

        assertTrackPlusEq(
            "userTokenBalance",
            0,
            vyToken.balanceOf(address(this))
        );
        assertEq(unit, IERC20(vyToken.underlying()).balanceOf(address(this)));
    }

    function testRedeemToSender() public {
        console.log("can redeem underlying to another user");
        track("userTokenBalance", vyToken.balanceOf(address(this)));
        track(
            "userUnderlyingBalance",
            IERC20(vyToken.underlying()).balanceOf(address(this))
        );

        IERC20(vyToken.underlying()).approve(
            address(ladle.joins(vyToken.underlyingId())),
            unit
        );
        vyToken.mint(address(this), unit);

        vyToken.redeem(user, unit);

        assertTrackPlusEq(
            "userTokenBalance",
            0,
            vyToken.balanceOf(address(this))
        );
        assertEq(unit, IERC20(vyToken.underlying()).balanceOf(user));
    }

    function testFlashFeeFactor() public {
        console.log("can set the flash fee factor");
        assertEq(vyToken.flashFeeFactor(), type(uint256).max);
        vyToken.setFlashFeeFactor(1);
        assertEq(vyToken.flashFeeFactor(), 1);
    }

    function testFuzz_convertToUnderlyingWithIncreasingRates(uint128 newRate)
        public
    {
        console.log(
            "amount of underlying received should increase as rate goes up"
        );
        uint256 underlyingAmount = vyToken.convertToUnderlying(INK);
        (uint256 oldPerSecondRate, , ) = chiRateOracle.sources(
            vyToken.underlyingId(),
            CHI
        );

        newRate = uint128(bound(newRate, oldPerSecondRate, type(uint128).max));
        chiRateOracle.updatePerSecondRate(vyToken.underlyingId(), CHI, newRate);
        vm.warp(block.timestamp + 1);
        (uint256 accumulated, uint256 updateTime) = chiRateOracle.get(
            vyToken.underlyingId(),
            CHI,
            0
        );

        assertLt(underlyingAmount, vyToken.convertToUnderlying(INK));
    }

    function testFuzz_convertToUnderlyingWithDecreasingRates(uint256 newRate)
        public
    {
        console.log(
            "amount of underlying received should decrease as rate goes down"
        );
        uint256 underlyingAmount = vyToken.convertToUnderlying(INK);
        (uint256 oldPerSecondRate, , ) = chiRateOracle.sources(
            vyToken.underlyingId(),
            CHI
        );

        newRate = bound(newRate, 1e18, type(uint256).max);
        chiRateOracle.updatePerSecondRate(vyToken.underlyingId(), CHI, newRate);
        chiRateOracle.get(vyToken.underlyingId(), CHI, 0);

        assertLe(underlyingAmount, vyToken.convertToUnderlying(INK));
    }

    function testFuzz_convertToPrincipalIncreasingRates(uint128 newRate)
        public
    {
        console.log("amount of principal should go down as rates go up");
        uint256 principalAmount = vyToken.convertToPrincipal(INK);
        (uint256 oldPerSecondRate, , ) = chiRateOracle.sources(
            vyToken.underlyingId(),
            CHI
        );

        newRate = uint128(bound(newRate, oldPerSecondRate, type(uint128).max));
        chiRateOracle.updatePerSecondRate(vyToken.underlyingId(), CHI, newRate);
        vm.warp(block.timestamp + 1);
        chiRateOracle.get(vyToken.underlyingId(), CHI, 0);

        assertGt(principalAmount, vyToken.convertToPrincipal(INK));
    }

    function testFuzz_convertToPrincipalDecreasingRates(uint256 newRate)
        public
    {
        console.log("amount of principal should go up as rates go down");
        uint256 principalAmount = vyToken.convertToPrincipal(INK);
        (uint256 oldPerSecondRate, , ) = chiRateOracle.sources(
            vyToken.underlyingId(),
            CHI
        );

        newRate = bound(newRate, 1e10, oldPerSecondRate - 1);
        chiRateOracle.updatePerSecondRate(vyToken.underlyingId(), CHI, newRate);
        chiRateOracle.get(vyToken.underlyingId(), CHI, 0);

        assertLe(principalAmount, vyToken.convertToPrincipal(INK));
    }
}

contract FlashLoanEnabledStateTests is FlashLoanEnabledState {
    function testReturnsCorrectMaxFlashLoan() public {
        console.log("can return the correct max flash loan");
        assertEq(vyToken.maxFlashLoan(address(vyToken)), type(uint256).max);
    }

    function testFlashBorrow() public {
        console.log("can do a simple flash borrow");

        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.NORMAL
        );

        assertEq(vyToken.balanceOf(address(this)), unit);
        assertEq(borrower.flashBalance(), unit);
        assertEq(borrower.flashToken(), address(vyToken));
        assertEq(borrower.flashAmount(), unit);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testRepayWithTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(vyToken), address(0), unit);

        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.TRANSFER
        );

        assertEq(vyToken.balanceOf(address(this)), unit);
        assertEq(borrower.flashBalance(), unit);
        assertEq(borrower.flashToken(), address(vyToken));
        assertEq(borrower.flashAmount(), unit);
        assertEq(borrower.flashFee(), 0);
        assertEq(borrower.flashInitiator(), address(borrower));
    }

    function testApproveNonInitiator() public {
        vm.expectRevert("ERC20: Insufficient approval");
        vm.prank(address(this));
        vyToken.flashLoan(
            borrower,
            address(vyToken),
            unit,
            bytes(abi.encode(0))
        );
    }

    function testEnoughFundsForLoanRepay() public {
        vm.expectRevert("ERC20: Insufficient balance");
        vm.prank(address(this));
        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.STEAL
        );
    }

    function testNestedFlashLoans() public {
        borrower.flashBorrow(
            address(vyToken),
            unit,
            FlashBorrower.Action.REENTER
        );
        vm.prank(address(this));
        assertEq(borrower.flashBalance(), unit * 3);
    }
}
