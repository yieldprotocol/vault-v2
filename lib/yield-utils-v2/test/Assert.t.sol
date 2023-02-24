// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/utils/Timelock.sol";
import { Assert } from "../src/utils/Assert.sol";
import { ERC20Mock } from "../src/mocks/ERC20Mock.sol";
import { TestExtensions } from "./utils/TestExtensions.sol";
import { TestConstants } from "./utils/TestConstants.sol";


using stdStorage for StdStorage;

abstract contract Deployed is Test, TestExtensions, TestConstants {

    Assert public assertContract;
    ERC20Mock public target;

    function setUpMock() public {
        assertContract = new Assert();
        target = new ERC20Mock("Test", "TST");
        target.mint(address(this), 1000);
        target.mint(address(target), 1000);
    }

    function setUpHarness(string memory network) public {
        setUpMock(); // TODO: Think about a test harness.
    }

    function setUp() public virtual {
        string memory network = vm.envString(NETWORK);
        if (!equal(network, LOCALHOST)) vm.createSelectFork(network);

        if (vm.envBool(MOCK)) setUpMock();
        else setUpHarness(network);

        vm.label(address(target), "target");
    }
}

contract DeployedTest is Deployed {

    function testTwoEqualValues() public view {
        assertContract.assertEq(1, 1);
    }

    function testTwoUnequalValues() public {
        vm.expectRevert("Not equal to expected");
        assertContract.assertEq(1, 2);
    }

    function testTwoEqualCalls() public {
        bytes memory actualCalldata = abi.encodeWithSelector(target.totalSupply.selector, address(target));
        bytes memory expectedCalldata = abi.encodeWithSelector(target.totalSupply.selector, address(target));
        assertContract.assertEq(address(target), actualCalldata, address(target), expectedCalldata);
    }

    function testTwoUnequalCalls() public {
        bytes memory actualCalldata = abi.encodeWithSelector(target.totalSupply.selector, address(target));
        bytes memory expectedCalldata = abi.encodeWithSelector(target.balanceOf.selector, address(target));
        vm.expectRevert("Not equal to expected");
        assertContract.assertEq(address(target), actualCalldata, address(target), expectedCalldata);
    }

    function testCallAndValue() public {
        bytes memory actualCalldata = abi.encodeWithSelector(target.totalSupply.selector, address(target));
        uint actual = target.totalSupply();
        assertContract.assertEq(address(target), actualCalldata, actual);
    }

    function testUnequalCallAndValue() public {
        bytes memory actualCalldata = abi.encodeWithSelector(target.totalSupply.selector, address(target));
        uint actual = target.balanceOf(address(target));
        vm.expectRevert("Not equal to expected");
        assertContract.assertEq(address(target), actualCalldata, actual);
    }

    function testEqAbs() public {
        assertContract.assertEqAbs(2, 1, 1);

        vm.expectRevert("Higher than expected");
        assertContract.assertEqAbs(3, 1, 1);

        vm.expectRevert("Lower than expected");
        assertContract.assertEqAbs(1, 3, 1);


        assertContract.assertEqAbs(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1500,
            500
        );

        assertContract.assertEqAbs(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target)),
            1000
        );
    }


    function testEqRel() public {
        assertContract.assertEqRel(2200, 2000, 1e17);

        vm.expectRevert("Higher than expected");
        assertContract.assertEqRel(2201, 2000, 1e17);

        vm.expectRevert("Lower than expected");
        assertContract.assertEqRel(1799, 2000, 1e17);


        assertContract.assertEqRel(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1100,
            1e17
        );

        assertContract.assertEqRel(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target)),
            1e18
        );
    }

    function testGreaterThan() public {
        assertContract.assertGt(2, 1);
        
        assertContract.assertGt(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1
        );

        assertContract.assertGt(
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target))
        );

        vm.expectRevert("Not greater than expected");
        assertContract.assertGt(1, 2);

        vm.expectRevert("Not greater than expected");
        assertContract.assertGt(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            2000
        );

        vm.expectRevert("Not greater than expected");
        assertContract.assertGt(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target))
        );
    }

    function testLessThan() public {
        assertContract.assertLt(1, 2);

        assertContract.assertLt(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            2000
        );
        
        assertContract.assertLt(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target))
        );

        vm.expectRevert("Not less than expected");
        assertContract.assertLt(2, 1);

        vm.expectRevert("Not less than expected");
        assertContract.assertLt(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1000
        );
        
        vm.expectRevert("Not less than expected");
        assertContract.assertLt(
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target))
        );
    }

    function testGreaterThanOrEqual() public {
        assertContract.assertGe(2, 1);

        assertContract.assertGe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1
        );
        
        assertContract.assertGe(
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target))
        );

        assertContract.assertGe(2, 2);

        assertContract.assertGe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1000
        );
        
        assertContract.assertGe(
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target))
        );

        vm.expectRevert("Not greater or equal to expected");
        assertContract.assertGe(1, 2);

        vm.expectRevert("Not greater or equal to expected");
        assertContract.assertGe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            2000
        );
        
        vm.expectRevert("Not greater or equal to expected");
        assertContract.assertGe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target))
        );
    }

    function testLessThanOrEqual() public {
        assertContract.assertLe(1, 2);

        assertContract.assertLe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            2000
        );
        
        assertContract.assertLe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target))
        );

        assertContract.assertLe(2, 2);
        
        assertContract.assertLe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1000
        );
        
        assertContract.assertLe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target))
        );

        vm.expectRevert("Not less or equal to expected");
        assertContract.assertLe(2, 1);

        vm.expectRevert("Not less or equal to expected");
        assertContract.assertLe(
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target)),
            1
        );

        vm.expectRevert("Not less or equal to expected");
        assertContract.assertLe(
            address(target),
            abi.encodeWithSelector(target.totalSupply.selector, address(target)),
            address(target),
            abi.encodeWithSelector(target.balanceOf.selector, address(target))
        );
    }
}