// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

interface IV1FYDai is IERC20 {
    function maturity() external view returns(uint256);
    function redeem(address, address, uint256) external returns (uint256);
}
