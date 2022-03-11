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

    event BalancesUpdated(bytes6 indexed assetId, uint128 ink, uint128 art);
    event FreeCollateralCalculated(int256 freeCollateral);

    EnumerableSet.Bytes6Set private assetsInUse;
    mapping(bytes6 => DataTypes.Balances) public balancesPerAsset;

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

        if (ink != 0) {
            _updateBalances(vault_.ilkId, ink, 0);
        }
        if (art != 0) {
            _updateBalances(series_.baseId, 0, art);
        }

        // If there is debt and we are less safe
        if (balances_.art > 0 && (ink < 0 || art > 0)) {
            require(_level(vault_, balances_, series_) >= 0, "Undercollateralised");
        }

        return balances_;
    }

    function getFreeCollateral() public returns (int256 freeCollateral) {
        (uint128 _collateralisationRatio, bytes6 _commonCurrency) = (collateralisationRatio, commonCcy);

        uint256 totalInk;
        uint256 totalArt;
        uint256 length = assetsInUse.length();

        for (uint256 index; index < length; ) {
            bytes6 assetId = assetsInUse.get(index);
            DataTypes.Balances memory _balances = balancesPerAsset[assetId];
            IOracle oracle = spotOracles[assetId][_commonCurrency].oracle;

            totalInk += _valueAsset(oracle, assetId, _commonCurrency, _balances.ink);
            totalArt += _valueAsset(oracle, assetId, _commonCurrency, _balances.art);

            unchecked {
                ++index;
            }
        }

        freeCollateral = totalInk.i256() - totalArt.wmul(_collateralisationRatio).i256();
        emit FreeCollateralCalculated(freeCollateral);
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
            if (assetId == valuationAsset) {
                value = amount;
            } else {
                (value, ) = oracle.get(assetId, valuationAsset, amount);
            }
        }
    }

    function _updateBalances(
        bytes6 assetId,
        int128 ink,
        int128 art
    ) internal {
        assetsInUse.add(assetId);
        DataTypes.Balances memory balances_ = balancesPerAsset[assetId];
        if (ink != 0) {
            balances_.ink = balances_.ink.add(ink);
        }
        if (art != 0) {
            balances_.art = balances_.art.add(art);
        }
        balancesPerAsset[assetId] = balances_;
        emit BalancesUpdated(assetId, balances_.ink, balances_.art);
    }
}
