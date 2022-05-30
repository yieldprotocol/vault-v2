// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "../mocks/WETH9Mock.sol";
import "../other/backd/HealerModule.sol";
import "./utils/Test.sol";

interface ILadleCustom {
    function addModule(address module, bool set) external;

    function moduleCall(address module, bytes calldata data) external payable returns (bytes memory result);
}

contract HealerModuleTest is Test {
    ICauldron public cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    IWETH9 public weth;
    WETH9Mock public wethMock;
    HealerModule public healer;

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI token address
    bytes6 public ilkId = 0x303100000000; // DAI
    bytes6 public seriesId = 0x303130370000; // ETH/DAI Sept 22 series
    bytes12 public vaultId;

    function setUp() public {
        wethMock = new WETH9Mock();
        weth = IWETH9(address(wethMock));
        healer = new HealerModule(cauldron, weth);
        vm.prank(0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        ILadleCustom(address(ladle)).addModule(address(healer), true);
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);
    }

    function testHeal() public {
        ILadleCustom(address(ladle)).moduleCall(
            address(healer), 
            abi.encodeWithSelector(healer.heal.selector, vaultId, 1, 0)
        );
    }
}