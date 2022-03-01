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
    int256 public peekFreeCollateralUSD;

    uint128 public collateralisationRatio;
    bytes6 public commonCcy; // Currency to use as common ground for all the ink & art

    constructor(
        uint128 _collateralisationRatio,
        bytes6 _commonCurrency,
        uint8 _commonCcyDecimals
    ) {
        collateralisationRatio = _collateralisationRatio * uint128(10**(18 - _commonCcyDecimals));
        commonCcy = _commonCurrency;
    }

    function setParams(
        uint128 _collateralisationRatio,
        bytes6 _commonCurrency,
        uint8 _commonCcyDecimals
    ) external auth {
        collateralisationRatio = _collateralisationRatio * uint128(10**(18 - _commonCcyDecimals));
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

        _pour(vault_.ilkId, ink, vault_.seriesId, art);

        return balances_;
    }

    function _pour(
        bytes6 inkId,
        int128 ink,
        bytes6 artId,
        int128 art
    ) internal {
        if (ink != 0) {
            assetsInUse.add(inkId);
            balancesPerAsset[inkId].ink = balancesPerAsset[inkId].ink.add(ink);
        }
        if (art != 0) {
            assetsInUse.add(artId);
            balancesPerAsset[artId].art = balancesPerAsset[artId].art.add(art);
        }

        require(getFreeCollateralUSD() >= 0, "Undercollateralised");
    }

    function getFreeCollateralUSD() public returns (int256) {
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

        peekFreeCollateralUSD = totalInk.i256() - totalArt.wmul(_collateralisationRatio).i256();
        return peekFreeCollateralUSD;
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
