// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

abstract contract BaseConverter is AccessControl {
    constructor(address _asset, address _wrappedAsset) {}

    // View functions
    function wrappedFrom(uint256 assets) external view virtual returns (uint256);

    function assetFrom(uint256 wrappedAssets) external view virtual returns (uint256);

    function wrappedFor(uint256 assets) external view virtual returns (uint256);

    function assetFor(uint256 wrappedAssets) external view virtual returns (uint256);

    // State modifier functions
    function wrap(address to) external virtual {}

    function unwrap(address to) external virtual {}
}
