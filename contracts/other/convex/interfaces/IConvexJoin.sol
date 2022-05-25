// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

interface IConvexJoin {
    function addVault(bytes12 vault_) external;

    function removeVault(bytes12 vaultId_, address account_) external;
}
