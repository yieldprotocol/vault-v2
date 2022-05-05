// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "./Test.sol";
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
}

contract StrictMock {
    fallback() external payable {
        revert("Not mocked!");
    }
}

contract LenientMock {
    fallback() external payable {}
}
