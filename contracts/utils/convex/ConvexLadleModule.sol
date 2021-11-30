// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import '@yield-protocol/vault-interfaces/ICauldron.sol';
import '@yield-protocol/vault-interfaces/IFYToken.sol';
import '@yield-protocol/vault-interfaces/DataTypes.sol';
import './interfaces/IConvexStakingWrapperYield.sol';
import '../../LadleStorage.sol';

/// @title Convex Ladle Module to handle vault addition
contract ConvexLadleModule is LadleStorage {
    constructor(ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) {}

    /// @notice Adds a vault to the user's vault list in the convex wrapper
    /// @param convexStakingWrapper The address of the convex wrapper to which the vault will be added
    /// @param vaultId The vaulId to be added
    function addVault(IConvexStakingWrapperYield convexStakingWrapper, bytes12 vaultId) external {
        if (vaultId == 0x000000000000000000000000) {
            convexStakingWrapper.addVault(cachedVaultId);
        } else {
            convexStakingWrapper.addVault(vaultId);
        }
    }
}
