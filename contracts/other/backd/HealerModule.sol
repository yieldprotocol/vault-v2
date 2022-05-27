// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "../../LadleStorage.sol";
import "../../utils/Giver.sol";

///@title Ladle module that allows any vault to be poured to as long as it adds collateral or repays debt
contract HealerModule is LadleStorage {
    constructor(ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) {}

    function heal(bytes12 vaultId_, address to, int128 ink, int128 art)
        external payable
    {
        require (ink >= 0, "Only add collateral");
        require (art <= 0, "Only repay debt");
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        _pour(vaultId, vault, to, ink, art);
    }

    function getVault(bytes12 vaultId_)
        internal view
        returns (bytes12 vaultId, DataTypes.Vault memory vault)
    {
        if (vaultId_ == bytes12(0)) { // We use the cache
            require (cachedVaultId != bytes12(0), "Vault not cached");
            vaultId = cachedVaultId;
        } else {
            vaultId = vaultId_;
        }
        vault = cauldron.vaults(vaultId);
    } 
}