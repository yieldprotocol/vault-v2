// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "./interfaces/IConvexJoin.sol";
import "../../LadleStorage.sol";

/// @title Convex Ladle Module to handle vault addition
contract ConvexModule is LadleStorage {
    constructor(ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) {}

    /// @notice Adds a vault to the user's vault list in the convex wrapper
    /// @param convexJoin The address of the convex wrapper to which the vault will be added
    /// @param vaultId The vaultId to be added
    function addVault(IConvexJoin convexJoin, bytes12 vaultId) external {
        if (vaultId == bytes12(0)) {
            convexJoin.addVault(cachedVaultId);
        } else {
            convexJoin.addVault(vaultId);
        }
    }

    /// @notice Removes a vault from the user's vault list in the convex wrapper
    /// @param convexJoin The address of the convex wrapper from which the vault will be removed
    /// @param vaultId The vaultId to be removed
    /// @param account The address of the user from whose list the vault is to be removed
    function removeVault(
        IConvexJoin convexJoin,
        bytes12 vaultId,
        address account
    ) external {
        if (vaultId == bytes12(0)) {
            convexJoin.removeVault(cachedVaultId, account);
        } else {
            convexJoin.removeVault(vaultId, account);
        }
    }
}
