// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "../LadleStorage.sol";

///@title Healer module for the Ladle
///@notice Allows any vault to be poured to as long as it adds collateral or repays debt
contract HealerModule is LadleStorage {
    using WMul for uint256;
    using CastU256I128 for uint256;

    ///@notice Creates a Healer module for the Ladle
    ///@param cauldron_ address of the Cauldron
    ///@param weth_ address of WETH
    constructor(ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) {}

    ///@notice allows anyone to add collateral or repay debt to a vault
    ///@param vaultId id for the vault
    ///@param ink amount of collateral to add
    ///@param art amount of debt to repay
    ///@dev art must be a negative integer to be repaid
    function heal(bytes12 vaultId, int128 ink, int128 art)
        external payable
    {
        require (ink >= 0, "Only add collateral");
        require (art <= 0, "Only repay debt");
        (, DataTypes.Vault memory vault) = getVault(vaultId);        
        cauldron.pour(vaultId, ink, art);

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.join(msg.sender, uint128(ink));
        }

        // Manage debt tokens
        if (art != 0) {
            DataTypes.Series memory series = getSeries(vault.seriesId);
            series.fyToken.burn(msg.sender, uint128(-art));
        }
    }

    /// @dev Obtains a vault by vaultId from the Cauldron, and verifies that msg.sender is the owner
    /// If bytes(0) is passed as the vaultId it tries to load a vault from the cache
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

    /// @dev Obtains a series by seriesId from the Cauldron, and verifies that it exists
    function getSeries(bytes6 seriesId)
        internal view returns(DataTypes.Series memory series)
    {
        series = cauldron.series(seriesId);
        require (series.fyToken != IFYToken(address(0)), "Series not found");
    }

    /// @dev Obtains a join by assetId, and verifies that it exists
    function getJoin(bytes6 assetId)
        internal view returns(IJoin join)
    {
        join = joins[assetId];
        require (join != IJoin(address(0)), "Join not found");
    }

}