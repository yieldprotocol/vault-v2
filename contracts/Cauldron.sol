// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./interfaces/IFYToken.sol";
import "./interfaces/IJoin.sol";
import "./interfaces/IOracle.sol";
import "./libraries/DataTypes.sol";


library Math {
    /// @dev Add a number (which might be negative) to a positive, and revert if the result is negative.
    function add(uint128 x, int128 y) internal pure returns (uint128 z) {
        require (y > 0 || x >= uint128(-y), "Result below zero");
        z = y > 0 ? x + uint128(y) : x - uint128(-y);
    }
}

library RMath { // Fixed point arithmetic in Ray units
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        uint256 _z = uint256(x) * uint256(y) / 1e27;
        require (_z <= type(uint128).max, "RMUL Overflow");
        z = uint128(_z);
    }

    /// @dev Multiply an integer amount by a fixed point factor in ray units, returning an integer amount
    function rmul(int128 x, uint128 y) internal pure returns (int128 z) {
        if (x < 0) return -int128(rmul(uint128(-x), y));                // TODO: SafeCast
        else return int128(rmul(uint128(x), y));                        // TODO: SafeCast
    }
}

contract Cauldron {
    using Math for uint128;
    using RMath for uint128;
    using RMath for int128;

    event AssetAdded(bytes6 indexed assetId, address indexed asset);
    event SeriesAdded(bytes6 indexed seriesId, bytes6 indexed baseId, address indexed fyToken);
    event IlkAdded(bytes6 indexed seriesId, bytes6 indexed ilkId);
    event SpotOracleAdded(bytes6 indexed baseId, bytes6 indexed ilkId, address indexed oracle, uint32 ratio);
    event RateOracleAdded(bytes6 indexed baseId, address indexed oracle);
    event MaxDebtSet(bytes6 indexed baseId, bytes6 indexed ilkId, uint128 max);

    event VaultBuilt(bytes12 indexed vaultId, address indexed owner, bytes6 indexed seriesId, bytes6 ilkId);
    event VaultTweaked(bytes12 indexed vaultId, bytes6 indexed seriesId, bytes6 indexed ilkId);
    event VaultDestroyed(bytes12 indexed vaultId);
    event VaultTransfer(bytes12 indexed vaultId, address indexed receiver);

    event VaultStirred(bytes12 indexed vaultId, bytes6 indexed seriesId, bytes6 indexed ilkId, int128 ink, int128 art);
    event VaultShaken(bytes12 indexed from, bytes12 indexed to, uint128 ink);

    // ==== Protocol data ====
    mapping (bytes6 => IERC20)                              public assets;          // Underlyings and collaterals available in Cauldron. 12 bytes still free.
    mapping (bytes6 => mapping(bytes6 => DataTypes.Debt))   public debt;            // [baseId][ilkId] Max and sum of debt per underlying and collateral.
    mapping (bytes6 => DataTypes.Series)                    public series;          // Series available in Cauldron. We can possibly use a bytes6 (3e14 possible series).
    mapping (bytes6 => mapping(bytes6 => bool))             public ilks;            // [seriesId][assetId] Assets that are approved as collateral for a series

    // mapping (bytes6 => IOracle)                             public chiOracles;      // Chi (savings rate) accruals oracle for the underlying
    mapping (bytes6 => IOracle)                             public rateOracles;     // Rate (borrowing rate) accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => DataTypes.Spot))   public spotOracles;     // [assetId][assetId] Spot price oracles

    // ==== Vault data ====
    mapping (bytes12 => DataTypes.Vault)                    public vaults;          // An user can own one or more Vaults, each one with a bytes12 identifier
    mapping (bytes12 => DataTypes.Balances)                 public vaultBalances;   // Both debt and assets
    mapping (bytes12 => uint32)                             public timestamps;      // If grater than zero, time that a vault was timestamped. Used for liquidation.

    // ==== Administration ====

    /// @dev Add a new Asset.
    function addAsset(bytes6 assetId, IERC20 asset)
        external
    {
        require (assets[assetId] == IERC20(address(0)), "Id already used");
        assets[assetId] = asset;
        emit AssetAdded(assetId, address(asset));
    }

    /// @dev Set the maximum debt for an underlying and ilk pair. Can be reset.
    function setMaxDebt(bytes6 baseId, bytes6 ilkId, uint128 max)
        external
    {
        require (assets[baseId] != IERC20(address(0)), "Asset not found");                  // 1 SLOAD
        require (assets[ilkId] != IERC20(address(0)), "Asset not found");                   // 1 SLOAD
        debt[baseId][ilkId].max = max;                                                      // 1 SSTORE
        emit MaxDebtSet(baseId, ilkId, max);
    }

    /// @dev Set a rate oracle. Can be reset.
    function setRateOracle(bytes6 baseId, IOracle oracle)
        external
    {
        require (assets[baseId] != IERC20(address(0)), "Asset not found");                  // 1 SLOAD
        rateOracles[baseId] = oracle;                                                       // 1 SSTORE                                                             // 1 SSTORE. Allows to replace an existing oracle.
        emit RateOracleAdded(baseId, address(oracle));
    }

    /// @dev Set a spot oracle and its collateralization ratio. Can be reset.
    function setSpotOracle(bytes6 baseId, bytes6 ilkId, IOracle oracle, uint32 ratio)
        external
    {
        require (assets[baseId] != IERC20(address(0)), "Asset not found");                  // 1 SLOAD
        require (assets[ilkId] != IERC20(address(0)), "Asset not found");                   // 1 SLOAD
        spotOracles[baseId][ilkId] = DataTypes.Spot({
            oracle: oracle,
            ratio: ratio                                                                    // With 2 decimals. 10000 == 100%
        });                                                                                 // 1 SSTORE. Allows to replace an existing oracle.
        emit SpotOracleAdded(baseId, ilkId, address(oracle), ratio);
    }

    /// @dev Add a new series
    function addSeries(bytes6 seriesId, bytes6 baseId, IFYToken fyToken)
        external
        /*auth*/
    {
        require (assets[baseId] != IERC20(address(0)), "Asset not found");                  // 1 SLOAD
        require (fyToken != IFYToken(address(0)), "Series need a fyToken");
        require (rateOracles[baseId] != IOracle(address(0)), "Rate oracle not found");      // 1 SLOAD
        require (series[seriesId].fyToken == IFYToken(address(0)), "Id already used");      // 1 SLOAD
        series[seriesId] = DataTypes.Series({
            fyToken: fyToken,
            maturity: fyToken.maturity(),
            baseId: baseId
        });                                                                                 // 1 SSTORE
        emit SeriesAdded(seriesId, baseId, address(fyToken));
    }

    /// @dev Add a new Ilk (approve an asset as collateral for a series).
    function addIlk(bytes6 seriesId, bytes6 ilkId)
        external
    {
        DataTypes.Series memory _series = series[seriesId];                                 // 1 SLOAD
        require (
            _series.fyToken != IFYToken(address(0)),
            "Series not found"
        );
        require (
            spotOracles[_series.baseId][ilkId].oracle != IOracle(address(0)),               // 1 SLOAD
            "Spot oracle not found"
        );
        ilks[seriesId][ilkId] = true;                                                       // 1 SSTORE
        emit IlkAdded(seriesId, ilkId);
    }

    // ==== Vault management ====

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(bytes6 seriesId, bytes6 ilkId)
        public
        returns (bytes12 vaultId)
    {
        require (ilks[seriesId][ilkId] == true, "Ilk not added");                           // 1 SLOAD
        vaultId = bytes12(keccak256(abi.encodePacked(msg.sender, block.timestamp)));        // Check (vaults[id].owner == address(0)), and increase the salt until a free vault id is found. 1 SLOAD per check.
        vaults[vaultId] = DataTypes.Vault({
            owner: msg.sender,
            seriesId: seriesId,
            ilkId: ilkId
        });                                                                                 // 1 SSTORE

        emit VaultBuilt(vaultId, msg.sender, seriesId, ilkId);
    }

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId)
        public
    {
        require (vaults[vaultId].owner == msg.sender, "Only vault owner");                  // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];                       // 1 SLOAD
        require (_balances.art == 0 && _balances.ink == 0, "Only empty vaults");            // 1 SLOAD
        // delete timestamps[vaultId];                                                      // 1 SSTORE REFUND
        delete vaults[vaultId];                                                             // 1 SSTORE REFUND
        emit VaultDestroyed(vaultId);
    }

    /// @dev Change a vault series and/or collateral types.
    /// We can change the series if there is no debt, or assets if there are no assets
    /// Doesn't check inputs, or collateralization level. Do that in public functions.
    function __tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        internal
    {
        require (ilks[seriesId][ilkId] == true, "Ilk not added");                           // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];                       // 1 SLOAD
        DataTypes.Vault memory _vault = vaults[vaultId];                                    // 1 SLOAD
        if (seriesId != _vault.seriesId) {
            require (_balances.art == 0, "Only with no debt");
            _vault.seriesId = seriesId;
        }
        if (ilkId != _vault.ilkId) {                                                        // If a new asset was provided
            require (_balances.ink == 0, "Only with no collateral");
            _vault.ilkId = ilkId;
        }
        vaults[vaultId] = _vault;                                                           // 1 SSTORE
        emit VaultTweaked(vaultId, seriesId, ilkId);
    }

    /// @dev Transfer a vault to another user.
    /// Doesn't check inputs, or collateralization level. Do that in public functions.
    function __give(bytes12 vaultId, address receiver)
        internal
    {
        vaults[vaultId].owner = receiver;                                                   // 1 SSTORE
        emit VaultTransfer(vaultId, receiver);
    }

    // ==== Asset and debt management ====

    /// @dev Move collateral between vaults.
    /// Doesn't check inputs, or collateralization level. Do that in public functions.
    function __shake(bytes12 from, bytes12 to, uint128 ink)
        internal
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        require (vaults[from].ilkId == vaults[to].ilkId, "Different collateral");               // 2 SLOAD
        DataTypes.Balances memory _balancesFrom = vaultBalances[from];                          // 1 SLOAD
        DataTypes.Balances memory _balancesTo = vaultBalances[to];                              // 1 SLOAD
        _balancesFrom.ink -= ink;
        _balancesTo.ink += ink;
        vaultBalances[from] = _balancesFrom;                                                    // 1 SSTORE
        vaultBalances[to] = _balancesTo;                                                        // 1 SSTORE
        emit VaultShaken(from, to, ink);

        return (_balancesFrom, _balancesTo);
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    /// Doesn't check inputs, or collateralization level. Do that in public functions.
    function __stir(bytes12 vaultId, int128 ink, int128 art)
        internal returns (DataTypes.Balances memory)
    {
        DataTypes.Vault memory _vault = vaults[vaultId];                                    // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];                       // 1 SLOAD
        DataTypes.Series memory _series = series[_vault.seriesId];                          // 1 SLOAD

        // For now, the collateralization checks are done outside to allow for underwater operation. That might change.
        if (ink != 0) {
            _balances.ink = _balances.ink.add(ink);
        }

        // TODO: Consider whether _roll should call __stir, or the next block be a private function.
        // Modify vault and global debt records. If debt increases, check global limit.
        if (art != 0) {
            DataTypes.Debt memory _debt = debt[_series.baseId][_vault.ilkId];               // 1 SLOAD
            if (art > 0) require (_debt.sum.add(art) <= _debt.max, "Max debt exceeded");
            _balances.art = _balances.art.add(art);
            _debt.sum = _debt.sum.add(art);
            debt[_series.baseId][_vault.ilkId] = _debt;                                     // 1 SSTORE
        }
        vaultBalances[vaultId] = _balances;                                                 // 1 SSTORE

        emit VaultStirred(vaultId, _vault.seriesId, _vault.ilkId, ink, art);
        return _balances;
    }

    // ---- Restricted processes ----
    // Usable only by a authorized modules that won't cheat on Cauldron.

    // Change series and debt of a vault.
    // The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    // TODO: Should we allow changing the collateral at the same time?
    /* function _roll(bytes12 vaultId, bytes6 seriesId, int128 art)
        public
        auth
    {
        require (vaults[vaultId].owner != address(0), "Vault not found");                   // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];                       // 1 SLOAD
        DataTypes.Series memory _series = series[vaultId];                                  // 1 SLOAD
        
        delete vaultBalances[vaultId];                                                      // -1 SSTORE
        __tweak(vaultId, seriesId, vaults[vaultId].ilkId);                                  // 1 SLOAD + Cost of `__tweak`

        // Modify vault and global debt records. If debt increases, check global limit.
        if (art != 0) {
            DataTypes.Debt memory _debt = debt[_series.baseId][_vault.ilkId];               // 1 SLOAD
            if (art > 0) require (_debt.sum.add(art) <= _debt.max, "Max debt exceeded");
            _balances.art = _balances.art.add(art);
            _debt.sum = _debt.sum.add(art);
            debt[_series.baseId][_vault.ilkId] = _debt;                                     // 1 SSTORE
        }
        vaultBalances[vaultId] = _balances;                                                 // 1 SSTORE
        require(__level(vaultId) >= 0, "Undercollateralized");                              // Cost of `level`
    } */

    /// @dev Manipulate a vault, ensuring it is collateralized afterwards.
    /// To be used by debt management contracts.
    function _stir(bytes12 vaultId, int128 ink, int128 art)
        public
        // auth                                                                             // 1 SLOAD
        returns (DataTypes.Balances memory balances)
    {
        require (vaults[vaultId].owner != address(0), "Vault not found");                   // 1 SLOAD
        balances = __stir(vaultId, ink, art);                                               // Cost of `__stir`
        if (balances.art > 0 && (ink < 0 || art > 0))                                       // If there is debt and we are less safe
            require(__level(vaultId) >= 0, "Undercollateralized");                          // Cost of `level`. TODO: Consider allowing if collateralization level either is healthy or improves.
        return balances;
    }

    /// @dev Give a non-timestamped vault to the caller, and timestamp it.
    /// To be used for liquidation engines.
    function _grab(bytes12 vaultId)
        public
        // auth                                                                             // 1 SLOAD
    {
        require (timestamps[vaultId] + 24*60*60 <= block.timestamp, "Timestamped");         // 1 SLOAD. Grabbing a vault protects it for a day from being grabbed by another liquidator.
        timestamps[vaultId] = uint32(block.timestamp);                                      // 1 SSTORE. TODO: SafeCast
        __give(vaultId, msg.sender);                                                        // Cost of `__give`
    }

    /// @dev Manipulate a vault, ensuring it is collateralization level improved.
    /// To be used by debt management contracts.
    function _slurp(bytes12 vaultId, int128 ink, int128 art)
        public
        // auth                                                                             // 1 SLOAD
        returns (DataTypes.Balances memory balances)
    {
        require (vaults[vaultId].owner != address(0), "Vault not found");                   // 1 SLOAD
        (int128 _level, int128 _diff) = __diff(vaultId, ink, art);                          // Cost of `__diff`
        require (_level >= 0 || _diff >= 0, "Healthy or improve");
        balances = __stir(vaultId, ink, art);                                               // Cost of `__stir`
        return balances;
    }

    // ---- Public processes ----

    /// @dev Change a vault series or collateral.
    function tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        public
    {
        require (vaults[vaultId].owner == msg.sender, "Only vault owner");                  // 1 SLOAD
        // __tweak checks that the series and the collateral both exist and that the collateral is approved for the series
        __tweak(vaultId, seriesId, ilkId);                                                  // Cost of `__give`
    }

    /// @dev Give a vault to another user.
    function give(bytes12 vaultId, address user)
        public
    {
        require (vaults[vaultId].owner == msg.sender, "Only vault owner");                  // 1 SLOAD
        __give(vaultId, user);                                                              // Cost of `__give`
    }

    // Move collateral between vaults.
    function shake(bytes12 from, bytes12 to, uint128 ink)
        public
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        require (vaults[from].owner == msg.sender, "Only vault owner");                     // 1 SLOAD
        require (vaults[to].owner != address(0), "Vault not found");                        // 1 SLOAD
        DataTypes.Balances memory _balancesFrom;
        DataTypes.Balances memory _balancesTo;
        (_balancesFrom, _balancesTo) = __shake(from, to, ink);                              // Cost of `__shake`
        if (_balancesFrom.art > 0) require(__level(from) >= 0, "Undercollateralized");      // Cost of `level`. TODO: Consider allowing if collateralization level either is healthy or 
        return (_balancesFrom, _balancesTo);
    }

    // ==== Accounting ====

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    /*
    function level(bytes12 vaultId) public view returns (int128) {
        DataTypes.Vault memory _vault = vaults[vaultId];                                    // 1 SLOAD
        require (_vault.owner != address(0), "Vault not found");                            // The vault existing is enough to be certain that the oracle exists.
        DataTypes.Series memory _series = series[_vault.seriesId];                          // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];                       // 1 SLOAD
        DataTypes.Spot memory _spotData = spotOracles[_series.baseId][_vault.ilkId];        // 1 SLOAD
        uint128 spot = oracle.spot();                                                       // 1 `spot` call
        uint128 ratio = uint128(_spotData.ratio) * 1e23;                                    // Normalization factor from 2 to 27 decimals

        if (block.timestamp >= _series.maturity) {
            IOracle rateOracle = rateOracles[_series.baseId];                               // 1 SLOAD
            uint128 accrual = rateOracle.accrual(_series.maturity);                         // 1 `accrual` call
            return int128(_balances.ink.rmul(spot)) - int128(_balances.art.rmul(accrual).rmul(ratio)); // TODO: SafeCast
        }

        return int128(_balances.ink.rmul(spot)) - int128(_balances.art.rmul(ratio));         // TODO: SafeCast
    }
    */

    /// @dev Return the collateralization level of a vault. Negative means undercollateralized.
    function level(bytes12 vaultId) public view returns (int128) {
        return __level(vaultId);                                                            // Cost of `__level`
    }

    /// @dev Return the relative collateralization level of a vault for a given change in debt and collateral. Negative means the collateralization level would drop.
    function diff(bytes12 vaultId, int128 dink, int128 dart) public view returns (int128) {
        (,int128 _diff) = __diff(vaultId, dink, dart);                                      // Cost of `__diff`
        return _diff;
    }

    /// @dev Return the collateralization level of a vault. Negative means undercollateralized.
    function __level(bytes12 vaultId) internal view returns (int128) {
        (int128 _level,) = __diff(vaultId, 0, 0);                                           // Cost of `__diff`
        return _level;
    }

    /// @dev Return the relative collateralization level of a vault for a given change in debt and collateral, as well as the collateralization level at the end.
    function __diff(bytes12 vaultId, int128 dink, int128 dart) internal view returns (int128, int128) {
        DataTypes.Vault memory _vault = vaults[vaultId];                                    // 1 SLOAD
        require (_vault.owner != address(0), "Vault not found");                            // The vault existing is enough to be certain that the oracle exists.
        DataTypes.Series memory _series = series[_vault.seriesId];                          // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];                       // 1 SLOAD
        DataTypes.Spot memory _spotData = spotOracles[_series.baseId][_vault.ilkId];        // 1 SLOAD
        uint128 ratio = uint128(_spotData.ratio) * 1e23;                                    // Normalization factor from 2 to 27 decimals | TODO: SafeCast
        uint128 spot = _spotData.oracle.spot();                                             // 1 `spot` call

        if (block.timestamp >= _series.maturity) {
            uint128 accrual = rateOracles[_series.baseId].accrual(_series.maturity);        // 1 SLOAD + 1 `accrual` call
            return (
                int128(_balances.ink.rmul(spot)) - int128(_balances.art.rmul(accrual).rmul(ratio)), // level
                dink.rmul(spot) - dart.rmul(accrual).rmul(ratio)                                    // diff
            );
        }

        return (
            int128(_balances.ink.rmul(spot)) - int128(_balances.art.rmul(ratio)),           // level
            dink.rmul(spot) - dart.rmul(ratio)                                              // diff
        );
    }
}