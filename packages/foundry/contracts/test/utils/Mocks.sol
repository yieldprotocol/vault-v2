// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "forge-std/src/Test.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";

//common utilities for forge tests
library Mocks  {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    function mock(string memory label) external returns (address mock_) {
        mock_ = address(new StrictMock());
        vm.label(mock_, label);
    }

    function lenientMock(string memory label) external returns (address mock_) {
        mock_ = address(new LenientMock());
        vm.label(mock_, label);
    }

    function mockAt(address where, string memory label) external returns (address) {
        vm.etch(where, vm.getCode("Mocks.sol:StrictMock"));
        vm.label(where, label);
        return where;
    }

    // ===================================== mock =====================================

    function mock(function (address) external f, address param1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1),
            abi.encode(0)
        );
    }

    function mock(function () external returns(uint256) f, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function mock(function () external returns(uint32) f, uint32 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function mock(function () external returns(int128) f, int128 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }
    
    function mock(function () external returns(uint112, uint112, uint32) f, uint112 returned1, uint112 returned2, uint32 returned3) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1, returned2, returned3)
        );
    }

    function mock(function (address) external returns(uint256) f, address param1, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1),
            abi.encode(returned1)
        );
    }

    function mock(function (bytes12) external returns(int) f, bytes12 param1, int returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1),
            abi.encode(returned1)
        );
    }

    function mock(function (bytes12) external view returns(DataTypes.Vault memory) f, bytes12 param1, DataTypes.Vault memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1),
            abi.encode(returned1)
        );
    }

    function mock(function (bytes12, address) external returns(DataTypes.Vault memory) f, bytes12 param1, address param2, DataTypes.Vault memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2),
            abi.encode(returned1)
        );
    }
    
    function mock(function (bytes12) external view returns(DataTypes.Balances memory) f, bytes12 param1, DataTypes.Balances memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1),
            abi.encode(returned1)
        );
    }

    function mock(function (bytes12, uint128, uint128) external returns(DataTypes.Balances memory) f, bytes12 param1, uint128 param2, uint128 param3, DataTypes.Balances memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2, param3),
            abi.encode(returned1)
        );
    }

    function mock(function (address, bytes12, bytes6, bytes6) external returns(DataTypes.Vault memory) f, address p1, bytes12 p2, bytes6 p3, bytes6 p4, DataTypes.Vault memory r1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, p1, p2, p3, p4),
            abi.encode(r1)
        );
    }

    function mock(function (bytes6, bytes6) external returns(DataTypes.Debt memory) f, bytes6 p1, bytes6 p2, DataTypes.Debt memory r1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, p1, p2),
            abi.encode(r1)
        );
    }

    function mock(function (bytes6) external view returns(DataTypes.Series memory) f, bytes6 param1, DataTypes.Series memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1),
            abi.encode(returned1)
        );
    }

    function mock(function (bytes6) external view returns(IJoin) f, bytes6 param1, IJoin returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1),
            abi.encode(returned1)
        );
    }

    function mock(function (bytes6, uint128) external returns(uint128) f, bytes6 param1, uint128 param2, uint128 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2),
            abi.encode(returned1)
        );
    }

    function mock(function (address, uint128) external returns(uint128) f, address param1, uint128 param2, uint128 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2),
            abi.encode(returned1)
        );
    }

    function mock(function (address, uint256) external f, address param1, uint256 param2) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2),
            abi.encode(0)
        );
    }

    // ===================================== verify =====================================

    function verify(function (address) external f, address param1) internal {
        vm.expectCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1)
        );
    }

    function verify(function (bytes12, address) external returns(DataTypes.Vault memory) f, bytes12 param1, address param2) internal {
        vm.expectCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2)
        );
    }

    function verify(function (address, uint128) external returns(uint128) f, address param1, uint128 param2) internal {
        vm.expectCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2)
        );
    }

     function verify(function (bytes12, uint128, uint128) external returns(DataTypes.Balances memory) f, bytes12 param1, uint128 param2, uint128 param3) internal {
        vm.expectCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2, param3)
        );
    }

     function verify(function (address, uint256) external f, address param1, uint256 param2) internal {
        vm.expectCall(
            f.address,
            abi.encodeWithSelector(f.selector, param1, param2)
        );
    }

    function verify(function (address, bytes12, bytes6, bytes6) external returns(DataTypes.Vault memory) f, address p1, bytes12 p2, bytes6 p3, bytes6 p4) internal {
        vm.expectCall(
            f.address,
            abi.encodeWithSelector(f.selector, p1, p2, p3, p4)
        );
    }
}

contract StrictMock {
    fallback() external payable {
        revert("Not mocked!");
    }
}

contract LenientMock {
    fallback() external payable {}
}
