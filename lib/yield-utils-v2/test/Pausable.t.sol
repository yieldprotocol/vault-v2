// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/utils/Pausable.sol";
import "./mocks/DummyWand.sol";

abstract contract StateZero is Test {
  event Paused(address indexed account, bool indexed state);

  Pausable public pausable;
  DummyWand public dummyWand;
  address deployer;

  function setUp() public virtual {
    vm.startPrank(deployer);

    deployer = address(1);
    vm.label(deployer, "deployer");

    pausable = new Pausable();
    vm.label(address(pausable), "Pausable contract");

    dummyWand = new DummyWand();
    vm.label(address(dummyWand), "DummmyWand contract");

    //... Granting permissions ...
    dummyWand.grantRole(DummyWand.actionWhenPaused.selector, deployer);
    dummyWand.grantRole(DummyWand.actionWhenNotPaused.selector, deployer);
    dummyWand.grantRole(Pausable.unpause.selector, deployer);
    dummyWand.grantRole(Pausable.pause.selector, deployer);

    vm.stopPrank();
  }
}

contract StateZeroTest is StateZero {
  function testNotPaused() public {
    console2.log("On deployment, _paused == false. Wand active.");
    vm.prank(deployer);

    vm.expectRevert(abi.encodeWithSelector(Pausable.RequireUnpaused.selector, deployer, false));
    dummyWand.actionWhenPaused();

    assertTrue(dummyWand.paused() == false);
  }

  function testActive() public {
    console2.log("On deployment, _paused == false. Contract active.");

    vm.prank(deployer);
    uint256 value = dummyWand.actionWhenNotPaused();

    assertTrue(value == 2);
    assertTrue(dummyWand.paused() == false);
  }
}

abstract contract StatePaused is StateZero {
  function setUp() public virtual override {
    super.setUp();

    vm.prank(deployer);
    // set paused == false
    dummyWand.pause();
    assertTrue(dummyWand.paused() == true);
  }
}

contract StatePausedTest is StatePaused {
  function testNotUnpaused() public {
    console2.log("Set paused == true. whenNotPaused to fail");

    vm.prank(deployer);
    vm.expectRevert(abi.encodeWithSelector(Pausable.RequirePaused.selector, deployer, true));
    dummyWand.actionWhenNotPaused();
  }

  function testPaused() public {
    console2.log("Set paused == true");

    vm.prank(deployer);
    uint256 value = dummyWand.actionWhenPaused();

    assertTrue(value == 1);
    assertTrue(dummyWand.paused() == true);
  }
}
