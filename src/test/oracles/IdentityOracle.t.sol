// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import {IdentityOracle} from "../../oracles/IdentityOracle.sol";
import {DAIMock} from "../../mocks/DAIMock.sol";
import {USDCMock} from "../../mocks/USDCMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {TestConstants} from "../utils/TestConstants.sol";

contract IdentityOracleTest is Test, TestConstants {
    DAIMock public dai;
    USDCMock public usdc;
    IdentityOracle public identityOracle;

    uint256 oneUSDC = 1e6;

    // Harness vars
    bytes6 public base;
    bytes6 public quote;
    uint128 public unitForBase;

    modifier onlyMock() {
        if (vm.envOr(MOCK, true)) _;
    }

    modifier onlyHarness() {
        if (vm.envOr(MOCK, true)) return;
        _;
    }

    function setUpMock() public {
        dai = new DAIMock();
        usdc = new USDCMock();
        identityOracle = new IdentityOracle();
        identityOracle.grantRole(
            IdentityOracle.setSource.selector,
            address(this)
        );
        identityOracle.setSource(USDC, DAI, usdc, dai);
    }

    function setUpHarness() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        identityOracle = IdentityOracle(vm.envAddress("ORACLE"));

        base = bytes6(vm.envBytes32("BASE"));
        quote = bytes6(vm.envBytes32("QUOTE"));
        unitForBase = uint128(
            10**ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals()
        );
    }

    function setUp() public {
        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testRevertOnUnknownSource() public onlyMock {
        vm.expectRevert("Source not found");
        identityOracle.get(bytes32(ETH), bytes32(USDC), WAD);
    }

    function testReturnsCorrectAmountForSameBaseAndQuote() public onlyMock {
        (uint256 amount, ) = identityOracle.get(DAI, DAI, WAD * 2500);
        assertEq(amount, WAD * 2500, "Conversion unsuccessful");
    }

    function testRetrieveFaceValueFromOracle() public onlyMock {
        uint256 amount;
        (amount, ) = identityOracle.get(bytes32(DAI), bytes32(DAI), WAD * 2500);
        assertEq(amount, WAD * 2500, "Conversion unsuccessful");
        (amount, ) = identityOracle.get(
            bytes32(USDC),
            bytes32(USDC),
            oneUSDC * 2500
        );
        assertEq(amount, oneUSDC * 2500, "Conversion unsuccessful");

        (amount, ) = identityOracle.peek(
            bytes32(DAI),
            bytes32(USDC),
            WAD * 2500
        );
        assertEq(amount, oneUSDC * 2500, "Conversion unsuccessful");
        (amount, ) = identityOracle.peek(
            bytes32(USDC),
            bytes32(DAI),
            oneUSDC * 2500
        );
        assertEq(amount, WAD * 2500, "Conversion unsuccessful");
    }

    function testConversionHarness() public onlyHarness {
        uint256 amount;
        uint256 updateTime;

        (amount, updateTime) = identityOracle.peek(base, quote, unitForBase);
        assertGt(updateTime, 0, "Update time below lower bound");
        assertLt(
            updateTime,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
            "Update time above upper bound"
        );
        assertApproxEqRel(amount, 1e8, 1e6);
        // and reverse
        (amount, updateTime) = identityOracle.peek(quote, base, 1e8);
        assertApproxEqRel(amount, unitForBase, unitForBase / 100);
    }
}
