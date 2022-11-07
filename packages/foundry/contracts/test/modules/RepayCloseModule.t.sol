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

abstract contract ZeroTest is Test, TestConstants { 
    ICauldron public cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    ILadle public ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    IWETH9 public weth;
    WETH9Mock public wethMock;
    RepayCloseModule public module;

    IERC20 public dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public fyDAI = IERC20(0x79A6Be1Ae54153AA6Fc7e4795272c63F63B2a6DC);
    IERC20 public usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public join = 0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc;           // DAI Join
    address public otherJoin = 0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4;      // USDC Join
    bytes6 public ilkId = 0x303100000000;                                       // DAI
    bytes6 public otherIlkId = 0x303200000000;                                  // USDC
    bytes6 public seriesId = 0x303130390000;                                    // ETH/DAI Dec 22 series
    bytes12 public vaultId;

    address public foo = address(1);
    address public bar = address(2);

    function setUp() public virtual {
        vm.createSelectFork('mainnet');
        // deployments
        wethMock = new WETH9Mock();
        weth = IWETH9(address(wethMock));
        module = new RepayCloseModule(cauldron, weth);
        // add module
        vm.prank(0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        ILadleCustom(address(ladle)).addModule(address(module), true);
    }
}

contract RepayCloseModuleTest is ZeroTest {
    function testOnlyBorrowAndPoolVault() public {
        console.log("can only be used with Borrow and Pool vaults");
        // Provide USDC ilkId instead of DAI
        (vaultId, ) = ladle.build(seriesId, otherIlkId, 0);
        deal(address(usdc), address(this), WAD * 10000);
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        usdc.approve(address(ladle), WAD * 10000);
        usdc.transfer(otherJoin, WAD * 10000);
        ladle.pour(vaultId, vault.owner, 1e18 * 10000, 1e18 * 5000);
        
        vm.prank(address(ladle));
        vm.expectRevert("Only for Borrow and Pool");
        ILadleCustom(address(ladle)).moduleCall(
            address(module),
            abi.encodeWithSelector(module.repayFromLadle.selector, vaultId, foo, bar)
        );
    }
}

contract WithVaultProvisioned is ZeroTest {
    function setUp() public override {
        super.setUp();
        // create vault
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);
        // provide tokens
        deal(address(dai), address(this), WAD * 6);
        deal(address(dai), address(ladle), WAD * 10);
        deal(address(fyDAI), address(ladle), WAD * 10);
        // provision vault
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        dai.approve(address(ladle), WAD * 6);
        dai.transfer(join, WAD * 6);
        ladle.pour(vaultId, vault.owner, 1e18 * 6, 1e18 * 3);
    }

    function testRepayFromLadle() public {
        console.log("Can repay from ladle");
        uint256 ladleBalanceBefore = fyDAI.balanceOf(address(ladle));
        uint256 joinBalanceBefore = dai.balanceOf(address(join));
        uint256 fooBalanceBefore = dai.balanceOf(address(foo));
        uint256 barBalanceBefore = fyDAI.balanceOf(address(bar));
                
        vm.prank(address(ladle));
        bytes memory data = ILadleCustom(address(ladle)).moduleCall(
            address(module),
            abi.encodeWithSelector(module.repayFromLadle.selector, vaultId, foo, bar)
        );
        uint256 repaid = abi.decode(data, (uint256));

        // the ladle will repay the 3 DAI vault debt in this case
        assertEq(repaid, WAD * 3);
        // the ladle will burn 3 fyDAI from its own balance, send the 
        // amount repaid (3) to foo from the join and then 
        // finally send its remaining fyToken balance (7 DAI) to bar
        assertEq(ladleBalanceBefore, fyDAI.balanceOf(address(ladle)) + WAD * 10);
        assertEq(joinBalanceBefore, dai.balanceOf(address(join)) + WAD * 3);
        assertEq(fooBalanceBefore, dai.balanceOf(address(foo)) - WAD * 3);
        assertEq(barBalanceBefore, fyDAI.balanceOf(address(bar)) - WAD * 7);
        // Both balances subtracted by 3 DAI since that is the amount repaid
        assertEq(cauldron.balances(vaultId).ink, WAD * 3);
        assertEq(cauldron.balances(vaultId).art, 0);
    }
}