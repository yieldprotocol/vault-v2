// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "../../interfaces/ICauldron.sol";
import "../../interfaces/ILadle.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "../../mocks/WETH9Mock.sol";
import "../../modules/RepayCloseModule.sol";
import "../utils/TestConstants.sol";

interface ILadleCustom {
    function addModule(address module, bool set) external;

    function moduleCall(address module, bytes calldata data) external payable returns (bytes memory result);
}

contract RepayCloseModuleTest is Test, TestConstants { 
    ICauldron public cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    IWETH9 public weth;
    WETH9Mock public wethMock;
    RepayCloseModule public module;

    IERC20 public dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI token address
    IERC20 public fyDAI = IERC20(0xFCb9B8C5160Cf2999f9879D8230dCed469E72eeb);
    address public join = 0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc;
    bytes6 public ilkId = 0x303100000000; // DAI
    bytes6 public seriesId = 0x303130370000; // ETH/DAI Dec 22 series
    bytes12 public vaultId;

    function setUp() public {
        vm.createSelectFork('mainnet');
        // deployments
        wethMock = new WETH9Mock();
        weth = IWETH9(address(wethMock));
        module = new RepayCloseModule(cauldron, weth);
        // add module
        vm.prank(0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        ILadleCustom(address(ladle)).addModule(address(module), true);
        // create vault
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);
        // provide tokens
        deal(address(dai), address(this), WAD * 2);
        deal(address(dai), address(ladle), WAD);
        deal(address(fyDAI), address(ladle), WAD);
        // provision vault
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        dai.approve(address(ladle), WAD * 2);
        dai.transfer(join, WAD * 2);
        ladle.pour(vaultId, vault.owner, 1e18 * 2, 1e18);

    }

    function testRepayFromLadle() public {
        console.log("Can repay from ladle");
        uint256 joinBalanceBefore = dai.balanceOf(address(join));
        uint256 baseBalanceBefore = dai.balanceOf(address(this));
        vm.prank(address(ladle));
        ILadleCustom(address(ladle)).moduleCall(
            address(module),
            abi.encodeWithSelector(module.repayFromLadle.selector, vaultId, address(this), address(this))
        );

        assertEq(joinBalanceBefore, dai.balanceOf(address(join)) + WAD);
        assertEq(baseBalanceBefore, dai.balanceOf(address(this)) - WAD);
        assertEq(cauldron.balances(vaultId).ink, WAD);
        assertEq(cauldron.balances(vaultId).art, 0);
    }

    function testCloseFromLadle() public {
        console.log("Can close from ladle");
        uint256 joinBalanceBefore = dai.balanceOf(address(join));
        uint256 baseBalanceBefore = dai.balanceOf(address(this));
        vm.prank(address(ladle));
        ILadleCustom(address(ladle)).moduleCall(
            address(module),
            abi.encodeWithSelector(module.closeFromLadle.selector, vaultId, address(this), address(this))
        );

        assertEq(joinBalanceBefore, dai.balanceOf(address(join)));
        assertEq(baseBalanceBefore, dai.balanceOf(address(this)) - WAD);
        assertEq(cauldron.balances(vaultId).ink, WAD);
        assertEq(cauldron.balances(vaultId).art, 0);
    }
}