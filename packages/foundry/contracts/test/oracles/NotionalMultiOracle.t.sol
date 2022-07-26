// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "../../other/notional/NotionalMultiOracle.sol";
import "../../mocks/DAIMock.sol";
import "../../mocks/USDCMock.sol";
import "../utils/TestConstants.sol";

contract NotionalMultiOracleTest is Test, TestConstants {
    DAIMock public dai;
    USDCMock public usdc;
    NotionalMultiOracle public notionalMultiOracle;

    // FDAI and FUSDC id's not included in TestConstants
    bytes6 public constant FDAI = 0x10c9dd69d188;
    bytes6 public constant FUSDC = 0x0ab7c536ef37;
    uint256 oneUSDC = 1e6;
    uint256 oneFCASH = 1e8;

    function setUp() public {
        dai = new DAIMock();
        usdc = new USDCMock();
        notionalMultiOracle = new NotionalMultiOracle();
        notionalMultiOracle.grantRole(notionalMultiOracle.setSource.selector, address(this));
        notionalMultiOracle.setSource(FDAI, DAI, dai);
        notionalMultiOracle.setSource(FUSDC, USDC, usdc);
    }

    function testRevertOnUnknownSource() public {
        vm.expectRevert("Source not found");
        notionalMultiOracle.get(bytes32(FDAI), bytes32(USDC), oneFCASH);
    }

    function testReturnsCorrectAmountForSameBaseAndQuote() public {
        (uint256 amount,) = notionalMultiOracle.get(FDAI, FDAI, WAD * 2500);
        assertEq(amount, WAD * 2500, "Conversion unsuccessful");
    }

    function testRetrieveFaceValueFromOracle() public {
        uint256 amount;
        (amount,) = notionalMultiOracle.get(bytes32(FDAI), bytes32(DAI), oneFCASH * 2500);
        assertEq(amount, WAD * 2500, "Conversion unsuccessful");
        (amount,) = notionalMultiOracle.get(bytes32(FUSDC), bytes32(USDC), oneFCASH * 2500);
        assertEq(amount, oneUSDC * 2500, "Conversion unsuccessful");
        (amount,) = notionalMultiOracle.get(bytes32(DAI), bytes32(FDAI), WAD * 2500);
        assertEq(amount, oneFCASH * 2500, "Conversion unsuccessful");
        (amount,) = notionalMultiOracle.get(bytes32(USDC), bytes32(FUSDC), oneUSDC * 2500);
        assertEq(amount, oneFCASH * 2500, "Conversion unsuccessful");

        (amount,) = notionalMultiOracle.peek(bytes32(FDAI), bytes32(DAI), oneFCASH * 2500);
        assertEq(amount, WAD * 2500, "Conversion unsuccessful");
        (amount,) = notionalMultiOracle.peek(bytes32(FUSDC), bytes32(USDC), oneFCASH * 2500);
        assertEq(amount, oneUSDC * 2500, "Conversion unsuccessful");
        (amount,) = notionalMultiOracle.peek(bytes32(DAI), bytes32(FDAI), WAD * 2500);
        assertEq(amount, oneFCASH * 2500, "Conversion unsuccessful");
        (amount,) = notionalMultiOracle.peek(bytes32(USDC), bytes32(FUSDC), oneUSDC * 2500);
        assertEq(amount, oneFCASH * 2500, "Conversion unsuccessful");
    }
}