// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "../utils/Test.sol";
import {IEToken} from "../../oracles/euler/IEToken.sol";
import {ETokenMock} from "../../mocks/oracles/euler/ETokenMock.sol";
import {ETokenMultiOracle} from "../../oracles/euler/ETokenMultiOracle.sol";

abstract contract ZeroState is Test {
    ETokenMultiOracle public oracle;
    bytes6 public constant DAI = "1";
    bytes6 public constant eDAI = "2";
    IEToken eToken = IEToken(address(0x123));

    function setUp() public virtual {
        oracle = new ETokenMultiOracle();
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
    function testSetSource() public {
        oracle.setSource(DAI, eDAI, eToken);

        vm.expectEmit(true, true, true, true);
        emit SourceSet(DAI, eDAI, address(eToken), true);
        oracle.sources(eDAI, DAI);
    }
}

contract ETokenMultiOracleTest is Test {
    ETokenMultiOracle public oracle;
    bytes6 public constant DAI = "1";
    bytes6 public constant eDAI = "2";

    function setUp() public {
        oracle = new ETokenMultiOracle();
    }

    function testRevertOnUnknownPair() public {
        vm.expectRevert("Source not found");
        oracle.get(eDAI, DAI, 1e18);
    }

    function testOracleGet() public {
        bytes32 baseId = eDAI;
        bytes32 quoteId = DAI;
        uint256 amountBase = 1e18;

        ETokenMock eToken = new ETokenMock();

        vm.mockCall(
            address(eToken),
            abi.encodeWithSelector(IEToken.convertBalanceToUnderlying.selector, amountBase),
            abi.encode(0x777)
        );

        oracle.grantRole(bytes4(keccak256("setSource(bytes6,bytes6,address)")), address(this));

        oracle.setSource(DAI, eDAI, eToken);

        (uint256 result, ) = oracle.get(baseId, quoteId, amountBase);
        assertEq(result, 0x777);
    }

    //TODO test setSource needs role
}
