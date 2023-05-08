// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRouter {
    function route(address target, bytes calldata data)
        external payable
        returns (bytes memory result);
}
