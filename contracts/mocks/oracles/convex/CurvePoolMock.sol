// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import '../../../oracles/convex/ICurvePool.sol';

contract CurvePoolMock  is ICurvePool {
    uint256 public price;

    function set(uint256 price_) external {
        price = price_;
    }

    function get_virtual_price() external override view returns (uint256) {
        return price;
    }
}
