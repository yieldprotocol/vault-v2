// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDivUp.sol";
import "../constants/Constants.sol";
import "../Cauldron.sol";
import "./util/EnumerableSet.sol";

contract ContangoCauldron is Cauldron {
    using CauldronMath for uint128;
    using EnumerableSet for EnumerableSet.Bytes6Set;
    using CastU256I256 for uint256;
    using WMul for uint256;
    using WDivUp for uint256;

    EnumerableSet.Bytes6Set private assetsInUse;
    mapping(bytes6 => DataTypes.Balances) public balancesPerAsset;
    int256 public peekFreeCollateral;

    uint128 public collateralisationRatio; // Must be on commonCcy precision
    bytes6 public commonCcy; // Currency to use as common ground for all the ink & art

    constructor(uint128 _collateralisationRatio, bytes6 _commonCurrency) {
        collateralisationRatio = _collateralisationRatio;
        commonCcy = _commonCurrency;
    }

    function setCollateralisationRatio(uint128 _collateralisationRatio) external auth {
        collateralisationRatio = _collateralisationRatio;
    }

    function setCommonCurrency(bytes6 _commonCurrency) external auth {
        commonCcy = _commonCurrency;
    }

    function pour(
        bytes12 vaultId,
        int128 ink,
        int128 art
    ) external override auth returns (DataTypes.Balances memory) {
        (
            DataTypes.Vault memory vault_,
            DataTypes.Series memory series_,
            DataTypes.Balances memory balances_
        ) = vaultData(vaultId, true);

        balances_ = _pour(vaultId, vault_, balances_, series_, ink, art);

        _updateVaultBalancesPerAsset(series_, vault_, ink, art);

        return balances_;
    }

    function _updateVaultBalancesPerAsset(
        DataTypes.Series memory series,
        DataTypes.Vault memory vault,
        int128 ink,
        int128 art
    ) internal {
        if (ink != 0) {
            assetsInUse.add(vault.ilkId);
            balancesPerAsset[vault.ilkId].ink = balancesPerAsset[vault.ilkId].ink.add(ink);
        }
        if (art != 0) {
            assetsInUse.add(series.baseId);
            balancesPerAsset[series.baseId].art = balancesPerAsset[series.baseId].art.add(art);
        }

        require(getFreeCollateral() >= 0, "Undercollateralised");
    }

    function getFreeCollateral() public returns (int256) {
        (uint128 _collateralisationRatio, bytes6 _commonCurrency) = (collateralisationRatio, commonCcy);

        uint256 totalInk;
        uint256 totalArt;

        //TODO is this reading .length() from storage each time?
        for (uint256 index; index < assetsInUse.length(); index++) {
            bytes6 assetId = assetsInUse.get(index);
            DataTypes.Balances memory _balances = balancesPerAsset[assetId];
            if (assetId != _commonCurrency && (_balances.ink > 0 || _balances.art > 0)) {
                IOracle oracle = spotOracles[assetId][_commonCurrency].oracle;
                totalInk += _valueAsset(oracle, assetId, _commonCurrency, _balances.ink);
                totalArt += _valueAsset(oracle, assetId, _commonCurrency, _balances.art);
            } else {
                //TODO maybe remove unsed asset?
                totalInk += _balances.ink;
                totalArt += _balances.art;
            }
        }

        peekFreeCollateral = totalInk.i256() - totalArt.wmul(_collateralisationRatio).i256();
        return peekFreeCollateral;
    }

    function _valueAsset(
        IOracle oracle,
        bytes6 assetId,
        bytes6 valuationAsset,
        uint256 amount
    ) internal returns (uint256 value) {
        if (amount > 0) {
            (value, ) = oracle.get(assetId, valuationAsset, amount);
        } else {
            value = 0;
        }
    }
}
