// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@yield-protocol/vault-interfaces/ICauldron.sol";

interface IContangoCauldron is ICauldron {
    function peekFreeCollateralUSD() external returns (int256);
    function getFreeCollateralUSD() external returns (int256);
}