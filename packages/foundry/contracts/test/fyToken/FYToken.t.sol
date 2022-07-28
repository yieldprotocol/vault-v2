// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "../../Cauldron.sol";
import "../../Join.sol";
import "../../FYToken.sol";

contract FYTokenTest is Test {
    Cauldron public cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    FYToken public fyDAI = FYToken(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    Join public daiJoin = Join(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc);

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes6 public ilkId = 0x303100000000; // For DAI
    bytes6 public seriesId = 0x303130380000; // ETH/DAI Dec 22 series

    function setUp() public {
        bytes4[] memory joinRoles = new bytes4[](2);
        joinRoles[0] = daiJoin.join.selector;
        joinRoles[1] = daiJoin.exit.selector;

        daiJoin.grantRoles(joinRoles, address(fyDAI));
        daiJoin.grantRoles(joinRoles, address(this));

        bytes4[] memory fyTokenRoles = new bytes4[](3);
        fyTokenRoles[0] = fyDAI.mint.selector;
        fyTokenRoles[1] = fyDAI.burn.selector;
        fyTokenRoles[2] = fyDAI.point.selector;
        fyDAI.grantRoles(fyTokenRoles, address(this));
    }
}