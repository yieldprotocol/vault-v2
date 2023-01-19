// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { NotionalMultiOracle } from "../../other/notional/NotionalMultiOracle.sol";
import { DAIMock } from "../../mocks/DAIMock.sol";
import { USDCMock } from "../../mocks/USDCMock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";

contract NotionalMultiOracleTest is Test, TestConstants {
    DAIMock public dai;
    USDCMock public usdc;
    NotionalMultiOracle public notionalMultiOracle;

    // FDAI and FUSDC id's not included in TestConstants
    bytes6 public constant FDAI = 0x10c9dd69d188;
    bytes6 public constant FUSDC = 0x0ab7c536ef37;
    uint256 oneUSDC = 1e6;
    uint256 oneFCASH = 1e8;

    // Harness vars
    bytes6 public base;
    bytes6 public quote;
    uint128 public unitForBase;

    modifier onlyMock() {
        if (vm.envOr(MOCK, true))
        _;
    }

    modifier onlyHarness() {
        if (vm.envOr(MOCK, true)) return;
        _;
    }


    function setUpMock() public {
        dai = new DAIMock();
        usdc = new USDCMock();
        notionalMultiOracle = new NotionalMultiOracle();
        notionalMultiOracle.grantRole(notionalMultiOracle.setSource.selector, address(this));
        notionalMultiOracle.setSource(FDAI, DAI, dai);
        notionalMultiOracle.setSource(FUSDC, USDC, usdc);
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        notionalMultiOracle = NotionalMultiOracle(vm.envAddress("ORACLE"));

        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        unitForBase = uint128(10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals());
    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testRevertOnUnknownSource() public onlyMock {
        vm.expectRevert("Source not found");
        notionalMultiOracle.get(bytes32(FDAI), bytes32(USDC), oneFCASH);
    }

    function testReturnsCorrectAmountForSameBaseAndQuote() public onlyMock {
        (uint256 amount,) = notionalMultiOracle.get(FDAI, FDAI, WAD * 2500);
        assertEq(amount, WAD * 2500, "Conversion unsuccessful");
    }

    function testRetrieveFaceValueFromOracle() public onlyMock {
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

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;
        // all fcash have 8 decimals
        (amount, updateTime) = notionalMultiOracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(updateTime, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "Update time above upper bound");
        assertApproxEqRel(amount, 1e8, 1e6);
        // and reverse
        (amount, updateTime) = notionalMultiOracle.peek(quote, base, 1e8);
        assertApproxEqRel(amount, unitForBase, unitForBase / 100);
    }
}