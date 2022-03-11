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

        int256 _prevFreeCollateral = peekFreeCollateral;

        _updateVaultBalancesPerAsset(series_, vault_, ink, art);

        // If there is debt and we are less safe
        if (balances_.art > 0 && (ink < 0 || art > 0)) {
            require(_level(vault_, balances_, series_) >= 0, "Vault Undercollateralised");
            int256 _currentFreeCollateral = peekFreeCollateral;
            if (_currentFreeCollateral < 0) {
                require(_currentFreeCollateral >= _prevFreeCollateral, "Cauldron Undercollateralised");
            }
        }

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

        getFreeCollateral();
    }

    function getFreeCollateral() public returns (int256 _peekFreeCollateral) {
        (uint128 _collateralisationRatio, bytes6 _commonCurrency) = (collateralisationRatio, commonCcy);

        uint256 totalInk;
        uint256 totalArt;
        uint256 length = assetsInUse.length();

        for (uint256 index; index < length; ) {
            bytes6 assetId = assetsInUse.get(index);
            DataTypes.Balances memory _balances = balancesPerAsset[assetId];
            IOracle oracle = spotOracles[assetId][_commonCurrency].oracle;

            if (_balances.ink > 0) {
                totalInk += assetId == _commonCurrency
                    ? _balances.ink
                    : _valueAsset(oracle, assetId, _commonCurrency, _balances.ink);
            }
            if (_balances.art > 0) {
                totalArt += assetId == _commonCurrency
                    ? _balances.art
                    : _valueAsset(oracle, assetId, _commonCurrency, _balances.art);
            }

            unchecked {
                ++index;
            }
        }

        _peekFreeCollateral = totalInk.i256() - totalArt.wmul(_collateralisationRatio).i256();
        peekFreeCollateral = _peekFreeCollateral;
    }

    function assetsInUseLength() external view returns (uint256) {
        return assetsInUse.length();
    }

    function pruneAssetsInUse() external returns (uint256) {
        bytes6 _commonCurrency = commonCcy;
        uint256 length = assetsInUse.length();

        for (uint256 index; index < length; ) {
            bytes6 assetId = assetsInUse.get(index);
            DataTypes.Balances memory _balances = balancesPerAsset[assetId];

            if (assetId != _commonCurrency && _balances.ink == 0 && _balances.art == 0) {
                assetsInUse.remove(assetId);

                unchecked {
                    --length;
                }
            } else {
                unchecked {
                    ++index;
                }
            }
        }
        return length;
    }

    function _valueAsset(
        IOracle oracle,
        bytes6 assetId,
        bytes6 valuationAsset,
        uint256 amount
    ) internal returns (uint256 value) {
        if (amount > 0) {
            (value, ) = oracle.get(assetId, valuationAsset, amount);
        }
    }
}
