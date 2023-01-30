// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./Fixture.sol";
import "../../mocks/ERC20Mock.sol";

abstract contract ZeroState is Fixture {}

contract VRLadleAdminTests is ZeroState {
    // @notice Test ability to set borrowing fee
    function testSetBorrowingFee() public {
        ladle.setFee(1000);
        assertEq(ladle.borrowingFee(), 1000);
    }
}

contract VRLadleJoinAdminTests is ZeroState {
    // @notice Test not able to add join before adding ilk
    function testNoAddJoinWithoutIlk() public {
        vm.expectRevert("Asset not found");
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
    }

    // @notice Test not able to add join with a mismatched ilk
    function testAddJoinMismatch() public {
        cauldron.addAsset(usdcId, address(usdc));
        vm.expectRevert("Mismatched asset and join");
        ladle.addJoin(usdcId, IJoin(address(daiJoin)));
    }

    // @notice Test ability to add join
    function testAddJoin() public {
        cauldron.addAsset(usdcId, address(usdc));
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
        assertEq(address(ladle.joins(usdcId)), address(usdcJoin));
    }

    // @notice Test the same join for a second ilk of the same asset
    function testAddJoinSameAsset() public {
        cauldron.addAsset(usdcId, address(usdc));
        ladle.addJoin(usdcId, IJoin(address(usdcJoin)));
        cauldron.addAsset(otherIlkId, address(usdc));
        ladle.addJoin(otherIlkId, IJoin(address(usdcJoin)));
        assertEq(address(ladle.joins(usdcId)), address(usdcJoin));
        assertEq(address(ladle.joins(otherIlkId)), address(usdcJoin));
    }
}
