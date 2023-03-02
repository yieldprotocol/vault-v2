// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../Join.sol";
import "../../interfaces/ICauldronGov.sol";
import "../../interfaces/ICauldron.sol";
import "../../interfaces/ILadleGov.sol";
import "../../interfaces/ILadle.sol";
import "../../interfaces/IJoin.sol";
import "../../interfaces/IWitch.sol";
import "../../oracles/yieldspace/YieldSpaceMultiOracle.sol";
import "../../oracles/composite/CompositeMultiOracle.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";

/// @title A contract that allows configuring the cauldron and ladle within bounds
contract ContangoWand is AccessControl {
    using CauldronUtils for ICauldron;
    using Math for *;

    uint256 public constant WAD = 1e18;

    ICauldron public immutable contangoCauldron;
    ICauldron public immutable yieldCauldron;
    ILadle public immutable contangoLadle;
    ILadle public immutable yieldLadle;
    YieldSpaceMultiOracle public immutable yieldSpaceOracle;
    CompositeMultiOracle public immutable compositeOracle;
    address public immutable yieldTimelock;
    IWitch public immutable contangoWitch;

    struct WitchDefaults {
        uint32 duration;
        uint64 vaultProportion;
        uint64 intialDiscount;
    }

    WitchDefaults public witchDefaults;
    mapping(bytes6 => mapping(bytes6 => uint32)) public ratio;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Debt)) public debt;

    constructor(
        ICauldron contangoCauldron_,
        ICauldron yieldCauldron_,
        ILadle contangoLadle_,
        ILadle yieldLadle_,
        YieldSpaceMultiOracle yieldSpaceOracle_,
        CompositeMultiOracle compositeOracle_,
        address yieldTimelock_,
        IWitch contangoWitch_
    ) {
        contangoCauldron = contangoCauldron_;
        yieldCauldron = yieldCauldron_;
        contangoLadle = contangoLadle_;
        yieldLadle = yieldLadle_;
        yieldSpaceOracle = yieldSpaceOracle_;
        compositeOracle = compositeOracle_;
        yieldTimelock = yieldTimelock_;
        contangoWitch = contangoWitch_;
    }

    /// ----------------- Cauldron Governance -----------------

    /// @notice Copy the spotOracle and ratio from the master cauldron
    function copySpotOracle(bytes6 baseId, bytes6 ilkId) external auth {
        DataTypes.SpotOracle memory spotOracle_ = yieldCauldron.spotOracles(baseId, ilkId);
        contangoCauldron.setSpotOracle(baseId, ilkId, spotOracle_.oracle, spotOracle_.ratio);
    }

    /// @notice Copy the lending oracle from the master cauldron
    function copyLendingOracle(bytes6 baseId) external auth {
        _copyLendingOracle(baseId);
    }

    function _copyLendingOracle(bytes6 baseId) internal {
        contangoCauldron.setLendingOracle(baseId, yieldCauldron.lendingOracles(baseId));
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
    function addAsset(bytes6 assetId) external auth returns (address asset_) {
        asset_ = _addAsset(assetId);
    }

    function _addAsset(bytes6 assetId) internal returns (address asset_) {
        asset_ = yieldCauldron.assets(assetId);
        if (asset_ == address(0)) {
            asset_ = address(yieldCauldron.series(assetId).fyToken);
        }
        require(asset_ != address(0), "Asset not known to the Yield Cauldron");
        contangoCauldron.addAsset(assetId, asset_);
    }

    /// @notice Add a new series, if it exists in the Yield Cauldron
    function addSeries(bytes6 seriesId) external auth returns (DataTypes.Series memory series_) {
        series_ = yieldCauldron.series(seriesId);
        require(address(series_.fyToken) != address(0), "Series not known to the Yield Cauldron");
        if (contangoCauldron.assets(series_.baseId) == address(0)) {
            _addAsset(series_.baseId);
            _copyLendingOracle(series_.baseId);
            _copyJoin(series_.baseId);
        }

        AccessControl(address(series_.fyToken)).grantRole(IFYToken.mint.selector, address(contangoLadle));
        AccessControl(address(series_.fyToken)).grantRole(IFYToken.burn.selector, address(contangoLadle));

        AccessControl(address(series_.fyToken)).grantRole(IFYToken.burn.selector, address(contangoWitch));

        contangoCauldron.addSeries(seriesId, series_.baseId, series_.fyToken);
    }

    /// @notice Set the ratio for a given asset pair in the Cauldron, within bounds. Set the spot oracle always to the composite oracle.
    function setRatio(bytes6 baseId, bytes6 ilkId, uint32 ratio_) external auth {
        // If the ilkId is a series and boundaries are not set, set ratio to the default
        uint32 bound_ = ratio[baseId][ilkId];
        if (bound_ == 0) {
            bound_ = ratio[baseId][yieldCauldron.series(ilkId).baseId];
        }
        if (bound_ == 0) {
            bound_ = yieldCauldron.spotOracles(baseId, ilkId).ratio;
        }
        if (bound_ == 0) {
            bound_ = yieldCauldron.spotOracles(baseId, yieldCauldron.series(ilkId).baseId).ratio;
        }

        require(bound_ > 0, "Default ratio not set");
        require(ratio_ >= bound_, "Ratio out of bounds");

        contangoCauldron.setSpotOracle(baseId, ilkId, compositeOracle, ratio_);
    }

    /// @notice Bound ratio for a given asset pair
    function boundRatio(bytes6 baseId, bytes6 ilkId, uint32 ratio_) external auth {
        ratio[baseId][ilkId] = ratio_;
    }

    /// @notice Add ilks to series
    function addIlks(bytes6 seriesId, bytes6[] calldata ilkIds) external auth {
        contangoCauldron.addIlks(seriesId, ilkIds);
    }

    /// @notice Bound debt limits for a given asset pair
    function boundDebtLimits(bytes6 baseId, bytes6 ilkId, uint96 max, uint24 min, uint8 dec) external auth {
        debt[baseId][ilkId] = DataTypes.Debt({max: max, min: min, dec: dec, sum: 0});
    }

    /// @notice Set the debt limits for a given asset pair in the Cauldron, within bounds
    function setDebtLimits(bytes6 baseId, bytes6 ilkId, uint96 max, uint24 min, uint8 dec) external auth {
        // If the ilkId is a series and boundaries are not set, set them to default values
        DataTypes.Debt memory bounds_ = debt[baseId][ilkId];
        if (bounds_.max == 0) {
            bounds_ = debt[baseId][yieldCauldron.series(ilkId).baseId];
        }
        if (bounds_.max == 0) {
            bounds_ = yieldCauldron.debt(baseId, ilkId);
        }
        if (bounds_.max == 0) {
            bounds_ = yieldCauldron.debt(baseId, yieldCauldron.series(ilkId).baseId);
        }

        uint256 paramMultiplier = 10 ** dec;
        uint256 boundsMultiplier = 10 ** bounds_.dec;

        require(max * paramMultiplier <= bounds_.max * boundsMultiplier, "Max debt out of bounds");
        require(min * paramMultiplier >= bounds_.min * boundsMultiplier, "Min debt out of bounds");

        contangoCauldron.setDebtLimits(baseId, ilkId, max, min, dec);
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
            DataTypes.SpotOracle memory spotOracle_ = yieldCauldron.lookupSpotOracle(baseId, ilkId);
            compositeOracle.setSource(baseId, ilkId, spotOracle_.oracle);
        }
    }

    /// @notice Set a path in the Composite oracle, as long as the path is not overwriting anything
    function setCompositeOraclePath(bytes6 baseId, bytes6 quoteId, bytes6[] calldata path) external auth {
        // This is hideous, but's the only way to check if a path is already set
        try compositeOracle.paths(baseId, quoteId, 0) {
            revert("Path already set");
        } catch {
            compositeOracle.setPath(baseId, quoteId, path);
        }
    }

    /// ----------------- Ladle Governance -----------------

    /// @notice Propagate a pool to the Ladle from the Yield Ladle
    function addPool(bytes6 seriesId) external auth returns (IPool pool_) {
        pool_ = IPool(yieldLadle.pools(seriesId));
        require(address(pool_) != address(0), "Pool not known to the Yield Ladle");
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

    function copyJoin(bytes6 assetId) external auth {
        _copyJoin(assetId);
    }

    function _copyJoin(bytes6 assetId) internal {
        IJoin join = yieldLadle.joins(assetId);
        require(address(join) != address(0), "Join not known to the Yield Ladle");
        _addJoin(assetId, yieldLadle.joins(assetId));
    }

    function _addJoin(bytes6 assetId, IJoin join) internal {
        contangoLadle.addJoin(assetId, join);

        AccessControl(address(join)).grantRole(IJoin.join.selector, address(contangoLadle));
        AccessControl(address(join)).grantRole(IJoin.exit.selector, address(contangoLadle));

        AccessControl(address(join)).grantRole(IJoin.join.selector, address(contangoWitch));
        AccessControl(address(join)).grantRole(IJoin.exit.selector, address(contangoWitch));
    }

    // TODO Maybe check if the join exists before deploying?

    function deployJoin(bytes6 assetId) external auth returns (IJoin join) {
        address asset = contangoCauldron.assets(assetId);
        require(asset != address(0), "Asset not known to the Contango Cauldron");
        require(contangoLadle.joins(assetId) == IJoin(address(0)), "Join already known to the Contango Ladle");

        Join join_ = new Join(asset);
        join_.grantRole(join_.ROOT(), yieldTimelock);

        join = IJoin(address(join_));
        _addJoin(assetId, join);
    }

    /// ----------------- Witch Governance -----------------

    function setWitchDefaults(uint32 duration, uint64 vaultProportion, uint64 intialDiscount) external auth {
        witchDefaults = WitchDefaults(duration, vaultProportion, intialDiscount);
    }

    function setLineAndLimit(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 vaultProportion,
        uint64 collateralProportion,
        uint128 max
    ) external auth {
        contangoWitch.setLineAndLimit(ilkId, baseId, duration, vaultProportion, collateralProportion, max);
    }

    function configureWitch(bytes6 ilkId, bytes6 baseId, uint128 max) external auth {
        DataTypes.SpotOracle memory spotOracle_ = contangoCauldron.lookupSpotOracle(baseId, ilkId);

        contangoWitch.setLineAndLimit({
            ilkId: ilkId,
            baseId: baseId,
            duration: witchDefaults.duration,
            vaultProportion: witchDefaults.vaultProportion,
            collateralProportion: uint64((WAD + witchDefaults.intialDiscount).wdivup(uint256(spotOracle_.ratio) * 10 ** 12)),
            max: max
        });
    }

    function setAuctioneerReward(uint256 auctioneerReward) external auth {
        contangoWitch.setAuctioneerReward(auctioneerReward);
    }
}

library CauldronUtils {
    function lookupSpotOracle(ICauldron cauldron, bytes6 baseId, bytes6 ilkId)
        internal
        view
        returns (DataTypes.SpotOracle memory spotOracle_)
    {
        spotOracle_ = cauldron.spotOracles(baseId, ilkId);
        if (address(spotOracle_.oracle) == address(0)) {
            spotOracle_ = cauldron.spotOracles(ilkId, baseId);
        }
        require(address(spotOracle_.oracle) != address(0), "Spot oracle not known to the Cauldron");
    }
}
