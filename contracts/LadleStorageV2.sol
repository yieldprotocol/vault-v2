// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/vault-interfaces/src/IConverter.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./LadleStorage.sol";


/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
/// Note that AccessControl is now inherited from LadleStorage, because it comes with state variables.
contract LadleStorageV2 is LadleStorage, AccessControl() {
    event ConverterAdded(address indexed asset, IConverter indexed converter);

    mapping (address => IConverter) public converters; // Converter contracts between a Yield-Bearing Vault and its underlying.
}