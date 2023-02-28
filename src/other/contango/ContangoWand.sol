// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../interfaces/ICauldronGov.sol";
import "../../interfaces/ICauldron.sol";
import "../../interfaces/ILadleGov.sol";
import "../../interfaces/ILadle.sol";
import "../../interfaces/IJoin.sol";
import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";
import "../../oracles/composite/CompositeMultiOracle.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";

/// @title A contract that allows configuring the cauldron and ladle within bounds
contract ContangoWand is AccessControl {
    ICauldronGov public immutable contangoCauldron;
    ICauldron public immutable yieldCauldron;
    ILadleGov public immutable contangoLadle;
    ILadle public immutable yieldLadle;
    YieldSpaceMultiOracle public immutable yieldSpaceOracle;
    CompositeMultiOracle public immutable compositeOracle;

    mapping(bytes6 => mapping(bytes6 => uint32)) public ratio;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Debt)) public debt;

    DataTypes.Debt public defaultDebtLimits;
    uint32 public defaultRatio;

    constructor(
        ICauldronGov contangoCauldron_,
        ICauldron yieldCauldron_,
        ILadleGov contangoLadle_,
        ILadle yieldLadle_,
        YieldSpaceMultiOracle yieldSpaceOracle_,
        CompositeMultiOracle compositeOracle_
    ) {
        contangoCauldron = contangoCauldron_;
        yieldCauldron = yieldCauldron_;
        contangoLadle = contangoLadle_;
        yieldLadle = yieldLadle_;
        yieldSpaceOracle = yieldSpaceOracle_;
        compositeOracle = compositeOracle_;
    }

    /// ----------------- Cauldron Governance -----------------

    /// @notice Copy the spotOracle and ratio from the master cauldron
    function copySpotOracle(bytes6 baseId, bytes6 ilkId) external auth {
        DataTypes.SpotOracle memory spotOracle_ = yieldCauldron.spotOracles(baseId, ilkId);
        contangoCauldron.setSpotOracle(baseId, ilkId, spotOracle_.oracle, spotOracle_.ratio);
    }

    /// @notice Copy the lending oracle from the master cauldron
    function copyLendingOracle(bytes6 baseId) external auth {
        IOracle lendingOracle_ = yieldCauldron.lendingOracles(baseId);
        contangoCauldron.setLendingOracle(baseId, lendingOracle_);
    }

    /// @notice Copy the debt limits from the master cauldron
    function copyDebtLimits(bytes6 baseId, bytes6 ilkId) external auth {
        DataTypes.Debt memory debt_ = yieldCauldron.debt(baseId, ilkId);
        if (debt_.max == 0) {
            debt_ = yieldCauldron.debt(baseId, yieldCauldron.series(ilkId).baseId);
        }
        contangoCauldron.setDebtLimits(baseId, ilkId, debt_.max, debt_.min, debt_.dec);
    }

    /// @notice Add a new asset in the Cauldron, as long as it is an asset or fyToken known to the Yield Cauldron
    function addAsset(bytes6 assetId) external auth {
        address asset_ = yieldCauldron.assets(assetId);
        if (asset_ == address(0)) {
            asset_ = address(yieldCauldron.series(assetId).fyToken);
        }
        require(asset_ != address(0), "Asset not known to the Yield Cauldron");
        contangoCauldron.addAsset(assetId, asset_);
    }

    /// @notice Add a new series, if it exists in the Yield Cauldron
    function addSeries(bytes6 seriesId) external auth {
        DataTypes.Series memory series_ = yieldCauldron.series(seriesId);
        require(address(series_.fyToken) != address(0), "Series not known to the Yield Cauldron");
        contangoCauldron.addSeries(seriesId, series_.baseId, series_.fyToken);
    }

    /// @notice Set the ratio for a given asset pair in the Cauldron, within bounds. Set the spot oracle always to the composite oracle.
    function setRatio(bytes6 baseId, bytes6 ilkId, uint32 ratio_) external auth {
        // If the ilkId is a series and boundaries are not set, set ratio to the default
        uint32 bound_ = ratio[baseId][ilkId];
        if (bound_ == 0 && yieldCauldron.series(ilkId).fyToken != IFYToken(address(0))) {
            ratio[baseId][ilkId] = bound_ = defaultRatio;
        }
        require(bound_ > 0, "Default ratio not set");
        require(ratio_ >= bound_, "Ratio out of bounds");

        contangoCauldron.setSpotOracle(baseId, ilkId, compositeOracle, ratio_);
    }

    /// @notice Set the default ratio
    function setDefaultRatio(uint32 ratio_) external auth {
        defaultRatio = ratio_;
    }

    /// @notice Bound ratio for a given asset pair
    function boundRatio(bytes6 baseId, bytes6 ilkId, uint32 ratio_) external auth {
        ratio[baseId][ilkId] = ratio_;
    }

    /// @notice Add ilks to series
    function addIlks(bytes6 seriesId, bytes6[] calldata ilkIds) external auth {
        contangoCauldron.addIlks(seriesId, ilkIds);
    }

    function _getDebtDecimals(bytes6 baseId, bytes6 ilkId) internal view returns (uint8 dec) {
        // If the debt is already set in the cauldron, we use the decimals from there
        // Otherwise, we use the decimals of the base
        DataTypes.Debt memory cauldronDebt_ = ICauldron(address(contangoCauldron)).debt(baseId, ilkId);
        if (cauldronDebt_.sum != 0) {
            dec = cauldronDebt_.dec;
        } else {
            dec = IERC20Metadata(contangoCauldron.assets(baseId)).decimals();
        }
    }

    /// @notice Bound debt limits for a given asset pair
    function boundDebtLimits(bytes6 baseId, bytes6 ilkId, uint96 max, uint24 min) external auth {
        debt[baseId][ilkId] = DataTypes.Debt({max: max, min: min, dec: _getDebtDecimals(baseId, ilkId), sum: 0});
    }

    /// @notice Set the default debt limits
    function setDefaultDebtLimits(uint96 max, uint24 min) external auth {
        defaultDebtLimits = DataTypes.Debt({max: max, min: min, dec: 0, sum: 0});
    }

    /// @notice Set the debt limits for a given asset pair in the Cauldron, within bounds
    function setDebtLimits(bytes6 baseId, bytes6 ilkId, uint96 max, uint24 min) external auth {
        // If the ilkId is a series and boundaries are not set, set them to default values
        DataTypes.Debt memory bounds_ = debt[baseId][ilkId];

        if (bounds_.max == 0 && bounds_.min == 0) {
            bounds_ = defaultDebtLimits;
            require(bounds_.max > 0, "Default debt limits not set");
            bounds_.dec = _getDebtDecimals(baseId, ilkId);
        }

        require(max <= bounds_.max, "Max debt out of bounds");
        require(min >= bounds_.min, "Min debt out of bounds");

        contangoCauldron.setDebtLimits(baseId, ilkId, max, min, bounds_.dec);
    }

    /// ----------------- Oracle Governance -----------------

    /// @notice Set a pool as a source in the YieldSpace oracle, as long as:
    /// - It is a pool known to the Yield Ladle
    /// - The baseId matches the pool's baseId
    /// - The quoteId matches the pool's seriesId
    function setYieldSpaceOracleSource(bytes6 seriesId) external auth {
        IPool pool_ = IPool(yieldLadle.pools(seriesId));
        require(address(pool_) != address(0), "Pool not known to the Yield Ladle");
        DataTypes.Series memory series_ = yieldCauldron.series(seriesId);
        require(address(series_.fyToken) != address(0), "Series not known to the Yield Cauldron");
        require(address(series_.fyToken) == address(pool_.fyToken()), "fyToken mismatch"); // Sanity check

        yieldSpaceOracle.setSource(seriesId, series_.baseId, pool_);
    }

    /// @notice Set the YieldSpace oracle as the source for a given asset pair in the Composite oracle, provided the source is set in the YieldSpace oracle
    function setCompositeOracleSource(bytes6 baseId, bytes6 ilkId) external auth {
        DataTypes.Series memory series_ = yieldCauldron.series(ilkId);
        if (series_.fyToken != IFYToken(address(0))) {
            (IPool pool_,) = yieldSpaceOracle.sources(baseId, ilkId);
            require(address(pool_) != address(0), "YieldSpace oracle not set");
            compositeOracle.setSource(baseId, ilkId, yieldSpaceOracle);
        } else if (yieldCauldron.assets(ilkId) != address(0)) {
            DataTypes.SpotOracle memory spotOracle_ = yieldCauldron.spotOracles(baseId, ilkId);
            compositeOracle.setSource(baseId, ilkId, spotOracle_.oracle);
        }
    }

    /// @notice Set a path in the Composite oracle, as long as the path is not overwriting anything
    function setCompositeOraclePath(bytes6 baseId, bytes6 quoteId, bytes6[] calldata path) external auth {
        // This doesn't work because of the way Solidity handles arrays
        // require(compositeOracle.paths(baseId, quoteId, 0) == bytes6(0), "Path already set"); // We check that the first element in the path is empty
        compositeOracle.setPath(baseId, quoteId, path);
    }

    /// ----------------- Ladle Governance -----------------

    /// @notice Propagate a pool to the Ladle from the Yield Ladle
    function addPool(bytes6 seriesId) external auth {
        address pool_ = yieldLadle.pools(seriesId);
        require(pool_ != address(0), "Pool not known to the Yield Ladle");
        contangoLadle.addPool(seriesId, pool_);
    }

    /// @notice Propagate an integration to the Ladle from the Yield Ladle
    function addIntegration(address integration) external auth {
        contangoLadle.addIntegration(integration, yieldLadle.integrations(integration));
    }

    /// @notice Propagate a token to the Ladle from the Yield Ladle
    function addToken(address token) external auth {
        contangoLadle.addToken(token, yieldLadle.tokens(token));
    }

    /// @notice Add join to the Ladle.
    /// @dev These will often be used to hold fyToken, so it doesn't seem possible to put boundaries. However, it seems low risk. Famous last words.
    function addJoin(bytes6 assetId, address join) external auth {
        contangoLadle.addJoin(assetId, join);
    }
}
