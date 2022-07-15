// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "../../mocks/WETH9Mock.sol";
import "../../modules/HealerModule.sol";

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
    address public join = 0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc;
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
        console.log("Can add collateral and/or repay debt to a given vault");
        
        // Populate vault.owner with DAI 
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        deal(dai, address(this), 10 ** 18);        
        IERC20(dai).approve(address(join), 15000);
        
        // Provide initial values for art and ink
        ladle.pour(vaultId, vault.owner, 15000, 10000);

        vm.startPrank(address(ladle));

        // Provision ladle with 1 DAI to add 1 to art
        deal(dai, address(ladle), 1);
        IERC20(dai).approve(address(join), 1);
        // Provision ladle with 1 fyDAI to subtract 1 from ink
        deal(address(cauldron.series(seriesId).fyToken), address(ladle), 1);

        ILadleCustom(address(ladle)).moduleCall(
            address(healer), 
            abi.encodeWithSelector(healer.heal.selector, vaultId, 1, -1)
        );
        vm.stopPrank();

        assertEq(cauldron.balances(vaultId).ink, 15001);
        assertEq(int128(cauldron.balances(vaultId).art), 9999);
    }

    function testCannotAddDebt() public {
        console.log("Cannot add to debt");
        vm.expectRevert(bytes("Only repay debt"));
        ILadleCustom(address(ladle)).moduleCall(
            address(healer),
            abi.encodeWithSelector(healer.heal.selector, vaultId, 0, 1)
        );
    }

    function testCannotRemoveCollateral() public {
        console.log("Cannot remove collateral");
        vm.expectRevert(bytes("Only add collateral"));
        ILadleCustom(address(ladle)).moduleCall(
            address(healer),
            abi.encodeWithSelector(healer.heal.selector, vaultId, -1, 0)
        );
    }
}