// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "../../LadleStorage.sol";
import "../../utils/Giver.sol";

///@title Ladle module that allows any vault to be poured to as long as it adds collateral or repays debt
contract HealerModule is LadleStorage {
    using WMul for uint256;
    using CastU256I128 for uint256;

    constructor(ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) {}

    function heal(bytes12 vaultId_, int128 ink, int128 art)
        external payable
    {
        require (ink >= 0, "Only add collateral");
        require (art <= 0, "Only repay debt");
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series;
        if (art != 0) series = getSeries(vault.seriesId);

        int128 fee = ((series.maturity - block.timestamp) * uint256(int256(art)).wmul(borrowingFee)).i128();

        // Update accounting
        cauldron.pour(vaultId, ink, art + fee);

        // Manage collateral
        if (ink > 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.join(vault.owner, uint128(ink));
        }

        // Manage debt tokens
        if (art > 0) {
            series.fyToken.burn(msg.sender, uint128(-art));
        }

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

    function getSeries(bytes6 seriesId)
        internal view returns(DataTypes.Series memory series)
    {
        series = cauldron.series(seriesId);
        require (series.fyToken != IFYToken(address(0)), "Series not found");
    }

    function getJoin(bytes6 assetId)
        internal view returns(IJoin join)
    {
        join = joins[assetId];
        require (join != IJoin(address(0)), "Join not found");
    }

}