// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "../mocks/WETH9Mock.sol";
import "../other/backd/HealerModule.sol";
import "./utils/Test.sol";
import "./utils/Mocks.sol";
import {console} from "forge-std/console.sol";

interface ILadleCustom {
    function addModule(address module, bool set) external;

    function moduleCall(address module, bytes calldata data) external payable returns (bytes memory result);
}

contract HealerModuleTest is Test {
    using Mocks for *;

    ICauldron public cauldron;
    ILadle public ladle;
    HealerModule public healer;
    IWETH9 public weth;

    function setUp() public {
        weth = IWETH9(Mocks.mock("WETH9"));
        cauldron = ICauldron(Mocks.mock("Cauldron"));
        ladle = ILadle(Mocks.mock("Ladle"));
        healer = new HealerModule(cauldron, weth);

        ILadleCustom(address(ladle)).addModule(address(healer), true);
    }

    function testHeal() public {
        console.log("Should add collateral to vault");
        ILadleCustom(address(ladle)).moduleCall(address(healer), abi.encode());
    }
}