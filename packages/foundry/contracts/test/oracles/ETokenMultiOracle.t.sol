// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import {IEToken} from "../../oracles/euler/IEToken.sol";
import {ETokenMultiOracle} from "../../oracles/euler/ETokenMultiOracle.sol";

abstract contract ZeroState is Test {
    ETokenMultiOracle public oracle;
    bytes6 public constant DAI = "1";
    bytes6 public constant eDAI = "2";
    IEToken eToken = IEToken(address(0x123));

    function setUp() public virtual {
        oracle = new ETokenMultiOracle();

        vm.label(address(eToken), "eToken");
    }
}

contract ZeroStateTest is ZeroState {
    function testRevertOnUnknownPair() public {
        vm.expectRevert("Source not found");
        oracle.get(eDAI, DAI, 1e18);
    }

    function testRevertOnSetSource() public {
        vm.expectRevert("Access denied");
        oracle.setSource(DAI, eDAI, eToken);
    }
}

abstract contract PermissionedState is ZeroState {
    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, address indexed source, bool inverse);

    function setUp() public virtual override {
        super.setUp();
        oracle.grantRole(bytes4(keccak256("setSource(bytes6,bytes6,address)")), address(this));
    }
}

contract PermissionedStateTest is PermissionedState {
    function testSetSourceSetsRegularSource() public {
        vm.expectEmit(true, true, true, true);
        emit SourceSet(eDAI, DAI, address(eToken), false);
        
        oracle.setSource(DAI, eDAI, eToken);

        (address source, bool inverse) = oracle.sources(eDAI, DAI);
        assertEq(source, address(eToken));
        assertFalse(inverse);
    }

    function testSetSourceSetsInverseSource() public {
        vm.expectEmit(true, true, true, true);
        emit SourceSet(DAI, eDAI, address(eToken), true);
        
        oracle.setSource(DAI, eDAI, eToken);

        (address source, bool inverse) = oracle.sources(DAI, eDAI);
        assertEq(source, address(eToken));
        assertTrue(inverse);
    }
}

abstract contract SourceSetState is PermissionedState {
    function setUp() public virtual override {
        super.setUp();

        oracle.setSource(DAI, eDAI, eToken);
    }
}

contract SourceSetStateTest is SourceSetState {
    function testOracleGetAndPeekETokenToUnderlying() public {
        uint256 amountBase = 123456789;
        uint256 expectedQuote = 0x777;

        vm.mockCall(
            address(eToken),
            abi.encodeWithSelector(IEToken.convertBalanceToUnderlying.selector, amountBase),
            abi.encode(expectedQuote)
        );

        (uint256 result, uint256 updateTime) = oracle.get(eDAI, DAI, amountBase);
        assertEq(result, expectedQuote);
        assertEq(updateTime, block.timestamp);

        (result, updateTime) = oracle.peek(eDAI, DAI, amountBase);
        assertEq(result, expectedQuote);
        assertEq(updateTime, block.timestamp);
    }

    function testOracleGetAndPeekUnderlyingToEToken() public {
        uint256 amountBase = 987654321;
        uint256 expectedQuote = 0x333;

        vm.mockCall(
            address(eToken),
            abi.encodeWithSelector(IEToken.convertUnderlyingToBalance.selector, amountBase),
            abi.encode(expectedQuote)
        );

        (uint256 result, uint256 updateTime) = oracle.get(DAI, eDAI, amountBase);
        assertEq(result, expectedQuote);
        assertEq(updateTime, block.timestamp);

        (result, updateTime) = oracle.peek(DAI, eDAI, amountBase);
        assertEq(result, expectedQuote);
        assertEq(updateTime, block.timestamp);
    }
}
