// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./LadleStorage.sol";

interface IConverter {
    function asset() external view returns (address);
    function wrappedFor(uint256 assets) external returns (uint256);
    function unwrap(address to) external returns (uint256);
}

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
/// Note that AccessControl is now inherited from LadleStorage, because it comes with state variables.
contract LadleStorageV2 is LadleStorage, AccessControl() {
    event ConverterAdded(address indexed asset, IConverter indexed converter);

    mapping (address => IConverter) public converters; // Converter contracts between a Yield-Bearing Vault and its underlying.

    constructor (ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) { }
}