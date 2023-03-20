// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "../../interfaces/IOracle.sol";
import "../../interfaces/IJoin.sol";
import "../../mocks/ERC20Mock.sol";
import "../../Join.sol";
import "../../variable/VYToken.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract VYTokenUpgrade {

    ERC20Mock public base;
    Join public join;
    VYToken public vyToken;
    VYToken public vyTokenV2;
    ERC1967Proxy public proxy;

    function setUp() public {
        base = new ERC20Mock("Base", "BASE");
        join = new Join(address(base));
        vyToken = new VYToken(0x303100000000, IOracle(address(0)), join, base.name(), base.symbol());
        proxy = new ERC1967Proxy(address(vyToken), abi.encodeWithSignature("initialize(address)", address(this)));

        vyTokenV2 = new VYToken(0x303100000000, IOracle(address(1)), join, base.name(), base.symbol());
    }
}

contract VYTokenUpgradeTest is VYTokenUpgrade, Test {
    // Test that the storage is initialized
    function testStorageInitialized() public {
        VYToken vyToken = VYToken(address(proxy));
        assertTrue(vyToken.initialized());
    }

    // Test that the storage can't be initialized again
    function testInitializeRevertsIfInitialized() public {
        VYToken vyToken = VYToken(address(proxy));

        vyToken.grantRole(VYToken.initialize.selector, address(this));
        
        vm.expectRevert("Already initialized");
        vyToken.initialize(address(this));
    }

    // Test that only authorized addresses can upgrade
    // Test that the storage can't be initialized again
    function testUpgradeToRevertsIfNotAuthed() public {
        VYToken vyToken = VYToken(address(proxy));

        vm.expectRevert("Access denied");
        vyToken.upgradeTo(address(vyTokenV2));
    }

    // Test that the upgrade works
    function testUpgradeTo() public {
        VYToken vyToken = VYToken(address(proxy));

        vyToken.grantRole(0x3659cfe6, address(this)); // upgradeTo(address)
        vyToken.upgradeTo(address(vyTokenV2));

        assertEq(address(vyToken.oracle()), address(1));
        assertTrue(vyToken.hasRole(vyToken.ROOT(), address(this)));
        assertTrue(vyToken.initialized());
    }
}
