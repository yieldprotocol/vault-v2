// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./utils/Test.sol";
import "./utils/Mocks.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";

interface ILadleCustom {
    function addModule(address module, bool set) external;

    function moduleCall(address module, bytes calldata data) external payable returns (bytes memory result);
}

contract HealerModuleTest is Test {
    using Mocks for *;

    ILadle public ladle;

    function setUp() public {
        ladle = ILadle(Mocks.mock("Ladle"));
        ILadleCustom(ladle).addModule(module, set);
    }
}