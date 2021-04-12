// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/AccessControl.sol";


library Math {
    /// @dev Add a number (which might be negative) to a positive, and revert if the result is negative.
    function add(uint128 x, int128 y) internal pure returns (uint128 z) {
        require (y > 0 || x >= uint128(-y), "Result below zero");
        z = y > 0 ? x + uint128(y) : x - uint128(-y);
    }
}

library DMath { // Fixed point arithmetic in 6 decimal units
    /// @dev Multiply an amount by a fixed point factor with 6 decimals, returning an amount
    function dmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            uint256 _z = uint256(x) * uint256(y) / 1e6;
            require (_z <= type(uint128).max, "DMUL Overflow");
            z = uint128(_z);
        }
    }
}

library RMath { // Fixed point arithmetic in Ray units
    /// @dev Multiply an integer amount by a fixed point factor in ray units, returning an integer amount
    function rmul(int128 x, uint128 y) internal pure returns (int128 z) {
        unchecked {
            int256 _z = int256(x) * int256(uint256(y)) / 1e27;
            require (_z >= type(int128).min && _z <= type(int128).max, "RMUL Overflow");
            z = int128(_z);
        }
    }
}

library Safe128 {
    /// @dev Safely cast an int128 to an uint128
    function u128(int128 x) internal pure returns (uint128 y) {
        require (x >= 0, "Cast overflow");
        y = uint128(x);
    }

    /// @dev Safely cast an uint128 to an int128
    function i128(uint128 x) internal pure returns (int128 y) {
        require (x <= uint128(type(int128).max), "Cast overflow");
        y = int128(x);
    }
}

library Safe256 {
    /// @dev Safely cast an uint256 to an int128
    function u32(uint256 x) internal pure returns (uint32 y) {
        require (x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }
}

// TODO: Add a setter for auction protection (same as Witch.AUCTION_TIME?)

contract Cauldron is AccessControl() {
    using Math for uint128;
    using DMath for uint128;
    using RMath for int128;
    using Safe256 for uint256;
    using Safe128 for uint128;
    using Safe128 for int128;

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

    event VaultPoured(bytes12 indexed vaultId, bytes6 indexed seriesId, bytes6 indexed ilkId, int128 ink, int128 art);
    event VaultStirred(bytes12 indexed from, bytes12 indexed to, uint128 ink, uint128 art);
    event VaultRolled(bytes12 indexed vaultId, bytes6 indexed seriesId, uint128 art);
    event VaultTimestamped(bytes12 indexed vaultId, uint256 indexed timestamp);

    // ==== Protocol data ====
    mapping (bytes6 => address)                                 public assets;          // Underlyings and collaterals available in Cauldron. 12 bytes still free.
    mapping (bytes6 => mapping(bytes6 => DataTypes.Debt))       public debt;            // [baseId][ilkId] Max and sum of debt per underlying and collateral.
    mapping (bytes6 => DataTypes.Series)                        public series;          // Series available in Cauldron. We can possibly use a bytes6 (3e14 possible series).
    mapping (bytes6 => mapping(bytes6 => bool))                 public ilks;            // [seriesId][assetId] Assets that are approved as collateral for a series

    mapping (bytes6 => IOracle)                                 public rateOracles;     // Rate (borrowing rate) accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => DataTypes.SpotOracle)) public spotOracles;     // [assetId][assetId] Spot price oracles

    // ==== Vault data ====
    mapping (bytes12 => DataTypes.Vault)                        public vaults;          // An user can own one or more Vaults, each one with a bytes12 identifier
    mapping (bytes12 => DataTypes.Balances)                     public balances;        // Both debt and assets
    mapping (bytes12 => uint32)                                 public timestamps;      // If grater than zero, time that a vault was timestamped. Used for liquidation.

    // ==== Administration ====

    /// @dev Add a new Asset.
    function addAsset(bytes6 assetId, address asset)
        external
        auth
    {
        require (assets[assetId] == address(0), "Id already used");
        assets[assetId] = asset;
        emit AssetAdded(assetId, address(asset));
    }

    /// @dev Set the maximum debt for an underlying and ilk pair. Can be reset.
    function setMaxDebt(bytes6 baseId, bytes6 ilkId, uint128 max)
        external
        auth
    {
        require (assets[baseId] != address(0), "Asset not found");
        require (assets[ilkId] != address(0), "Asset not found");
        debt[baseId][ilkId].max = max;
        emit MaxDebtSet(baseId, ilkId, max);
    }

    /// @dev Set a rate oracle. Can be reset.
    function setRateOracle(bytes6 baseId, IOracle oracle)
        external
        auth
    {
        require (assets[baseId] != address(0), "Asset not found");
        // TODO: The oracle should record the asset it refers to, and we should match it against assets[baseId]
        rateOracles[baseId] = oracle;
        emit RateOracleAdded(baseId, address(oracle));
    }

    /// @dev Set a spot oracle and its collateralization ratio. Can be reset.
    function setSpotOracle(bytes6 baseId, bytes6 ilkId, IOracle oracle, uint32 ratio)
        external
        auth
    {
        require (assets[baseId] != address(0), "Asset not found");
        require (assets[ilkId] != address(0), "Asset not found");
        // TODO: The oracle should record the assets it refers to, and we should match it against assets[baseId] and assets[ilkId]
        spotOracles[baseId][ilkId] = DataTypes.SpotOracle({
            oracle: oracle,
            ratio: ratio                                                                    // With 6 decimals. 1000000 == 100%
        });                                                                                 // Allows to replace an existing oracle.
        emit SpotOracleAdded(baseId, ilkId, address(oracle), ratio);
    }

    /// @dev Add a new series
    function addSeries(bytes6 seriesId, bytes6 baseId, IFYToken fyToken)
        external
        auth
    {
        address asset = assets[baseId];
        require (asset != address(0), "Asset not found");
        require (fyToken != IFYToken(address(0)), "Series need a fyToken");
        require (fyToken.asset() == asset, "Mismatched series and base");
        require (rateOracles[baseId] != IOracle(address(0)), "Rate oracle not found");
        require (series[seriesId].fyToken == IFYToken(address(0)), "Id already used");
        series[seriesId] = DataTypes.Series({
            fyToken: fyToken,
            maturity: fyToken.maturity().u32(),
            baseId: baseId
        });
        emit SeriesAdded(seriesId, baseId, address(fyToken));
    }

    /// @dev Add a new Ilk (approve an asset as collateral for a series).
    function addIlks(bytes6 seriesId, bytes6[] calldata ilkIds)
        external
        auth
    {
        DataTypes.Series memory series_ = series[seriesId];
        require (
            series_.fyToken != IFYToken(address(0)),
            "Series not found"
        );
        for (uint256 i = 0; i < ilkIds.length; i++) {
            require (
                spotOracles[series_.baseId][ilkIds[i]].oracle != IOracle(address(0)),
                "Spot oracle not found"
            );
            ilks[seriesId][ilkIds[i]] = true;
            emit IlkAdded(seriesId, ilkIds[i]);
        }
    }

    // ==== Vault management ====

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(address owner, bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        external
        auth
        returns(DataTypes.Vault memory vault)
    {
        require (vaults[vaultId].owner == address(0), "Vault already exists");
        require (ilks[seriesId][ilkId] == true, "Ilk not added");
        vault = DataTypes.Vault({
            owner: owner,
            seriesId: seriesId,
            ilkId: ilkId
        });
        vaults[vaultId] = vault;

        emit VaultBuilt(vaultId, owner, seriesId, ilkId);
    }

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId)
        external
        auth
    {
        DataTypes.Balances memory balances_ = balances[vaultId];
        require (balances_.art == 0 && balances_.ink == 0, "Only empty vaults");
        delete timestamps[vaultId];
        delete vaults[vaultId];
        emit VaultDestroyed(vaultId);
    }

    /// @dev Change a vault series and/or collateral types.
    function _tweak(bytes12 vaultId, DataTypes.Vault memory vault)
        internal
    {
        require (ilks[vault.seriesId][vault.ilkId] == true, "Ilk not added");

        vaults[vaultId] = vault;
        emit VaultTweaked(vaultId, vault.seriesId, vault.ilkId);
    }

    /// @dev Change a vault series and/or collateral types.
    /// We can change the series if there is no debt, or assets if there are no assets
    function tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        external
        auth
        returns(DataTypes.Vault memory vault)
    {
        // require (ilks[seriesId][ilkId] == true, "Ilk not added");
        DataTypes.Balances memory balances_ = balances[vaultId];
        vault = vaults[vaultId];
        if (seriesId != vault.seriesId) {
            require (balances_.art == 0, "Only with no debt");
            vault.seriesId = seriesId;
        }
        if (ilkId != vault.ilkId) {                                                        // If a new asset was provided
            require (balances_.ink == 0, "Only with no collateral");
            vault.ilkId = ilkId;
        }
        _tweak(vaultId, vault);
    }

    /// @dev Transfer a vault to another user.
    function _give(bytes12 vaultId, address receiver)
        internal
        returns(DataTypes.Vault memory vault)
    {
        vault = vaults[vaultId];
        vault.owner = receiver;
        vaults[vaultId] = vault;
        emit VaultTransfer(vaultId, receiver);
    }

    /// @dev Transfer a vault to another user.
    function give(bytes12 vaultId, address receiver)
        external
        auth
        returns(DataTypes.Vault memory vault)
    {
        vault = _give(vaultId, receiver);
    }

    // ==== Asset and debt management ====

    /// @dev Move collateral and debt between vaults.
    function stir(bytes12 from, bytes12 to, uint128 ink, uint128 art)
        external
        auth
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        DataTypes.Vault memory vaultFrom = vaults[from];
        DataTypes.Vault memory vaultTo = vaults[to];
        require (vaultFrom.owner != address(0), "Origin vault not found");
        require (vaultTo.owner != address(0), "Destination vault not found");

        DataTypes.Balances memory balancesFrom = balances[from];
        DataTypes.Balances memory balancesTo = balances[to];

        if (ink > 0) {
            require (vaultFrom.ilkId == vaultTo.ilkId, "Different collateral");
            balancesFrom.ink -= ink;
            balancesTo.ink += ink;
        }
        if (art > 0) {
            require (vaultFrom.seriesId == vaultTo.seriesId, "Different series");
            balancesFrom.art -= art;
            balancesTo.art += art;
        }

        balances[from] = balancesFrom;
        balances[to] = balancesTo;

        if (ink > 0) require(_level(vaultFrom, balancesFrom, series[vaultFrom.seriesId]) >= 0, "Undercollateralized at origin");
        if (art > 0) require(_level(vaultTo, balancesTo, series[vaultTo.seriesId]) >= 0, "Undercollateralized at destination");

        emit VaultStirred(from, to, ink, art);
        return (balancesFrom, balancesTo);
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    function _pour(
        bytes12 vaultId,
        DataTypes.Vault memory vault_,
        DataTypes.Balances memory balances_,
        DataTypes.Series memory series_,
        int128 ink,
        int128 art
    )
        internal returns (DataTypes.Balances memory)
    {
        // For now, the collateralization checks are done outside to allow for underwater operation. That might change.
        if (ink != 0) {
            balances_.ink = balances_.ink.add(ink);
        }

        // TODO: Consider whether _roll should call _pour, or the next block be a private function.
        // Modify vault and global debt records. If debt increases, check global limit.
        if (art != 0) {
            DataTypes.Debt memory debt_ = debt[series_.baseId][vault_.ilkId];
            if (art > 0) require (debt_.sum.add(art) <= debt_.max, "Max debt exceeded");
            balances_.art = balances_.art.add(art);
            debt_.sum = debt_.sum.add(art);
            debt[series_.baseId][vault_.ilkId] = debt_;
        }
        balances[vaultId] = balances_;

        emit VaultPoured(vaultId, vault_.seriesId, vault_.ilkId, ink, art);
        return balances_;
    }

    /// @dev Manipulate a vault, ensuring it is collateralized afterwards.
    /// To be used by debt management contracts.
    function pour(bytes12 vaultId, int128 ink, int128 art)
        external
        auth
        returns (DataTypes.Balances memory balances_)
    {
        DataTypes.Vault memory vault_ = vaults[vaultId];
        require (vault_.owner != address(0), "Vault not found");
        DataTypes.Series memory series_ = series[vault_.seriesId];
        balances_ = balances[vaultId];

        balances_ = _pour(vaultId, vault_, balances_, series_, ink, art);

        if (balances_.art > 0 && (ink < 0 || art > 0))                          // If there is debt and we are less safe
            require(_level(vault_, balances_, series_) >= 0, "Undercollateralized");
        return balances_;
    }

    /// @dev Give a non-timestamped vault to the caller, and timestamp it.
    /// To be used for liquidation engines.
    function grab(bytes12 vaultId)
        external
        auth
    {
        uint32 now_ = uint32(block.timestamp);
        require (timestamps[vaultId] + 24*60*60 <= now_, "Timestamped");        // Grabbing a vault protects it for a day from being grabbed by another liquidator. All grabbed vaults will be suddenly released on the 7th of February 2106, at 06:28:16 GMT. I can live with that.

        DataTypes.Vault memory vault_ = vaults[vaultId];
        require (vault_.owner != address(0), "Vault not found");
        DataTypes.Balances memory balances_ = balances[vaultId];
        DataTypes.Series memory series_ = series[vault_.seriesId];
        require(_level(vault_, balances_, series_) < 0, "Not undercollateralized");

        timestamps[vaultId] = now_;
        _give(vaultId, msg.sender);

        emit VaultTimestamped(vaultId, now_);
    }

    /// @dev Reduce debt and collateral from a vault, ignoring collateralization checks.
    /// To be used by liquidation engines.
    function slurp(bytes12 vaultId, uint128 ink, uint128 art)
        external
        auth
        returns (DataTypes.Balances memory balances_)
    {
        DataTypes.Vault memory vault_ = vaults[vaultId];
        require (vault_.owner != address(0), "Vault not found");
        DataTypes.Series memory series_ = series[vault_.seriesId];
        balances_ = balances[vaultId];

        balances_ = _pour(vaultId, vault_, balances_, series_, -(ink.i128()), -(art.i128()));

        return balances_;
    }

    /// @dev Change series and debt of a vault.
    /// The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    function roll(bytes12 vaultId, bytes6 newSeriesId, int128 art)
        external
        auth
        returns (uint128)
    {
        DataTypes.Vault memory vault_ = vaults[vaultId];
        require (vault_.owner != address(0), "Vault not found");
        DataTypes.Balances memory balances_ = balances[vaultId];
        DataTypes.Series memory oldSeries_ = series[vault_.seriesId];
        DataTypes.Series memory newSeries_ = series[newSeriesId];
        require (oldSeries_.baseId == newSeries_.baseId, "Mismatched bases in series");
        
        // Change the vault series, ignoring balance and debt checks
        vault_.seriesId = newSeriesId;
        _tweak(vaultId, vault_);

        // Modify vault and global debt records. If debt increases, check global limit.
        if (art != 0) {
            DataTypes.Debt memory debt_ = debt[oldSeries_.baseId][vault_.ilkId];
            if (art > 0) require (debt_.sum.add(art) <= debt_.max, "Max debt exceeded");
            balances_.art = balances_.art.add(art);
            debt_.sum = debt_.sum.add(art);
            debt[oldSeries_.baseId][vault_.ilkId] = debt_;
        }
        balances[vaultId] = balances_;

        require(_level(vault_, balances_, newSeries_) >= 0, "Undercollateralized");
        emit VaultRolled(vaultId, newSeriesId, balances_.art);
        return balances_.art;
    }

    // ==== Accounting ====

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    function level(bytes12 vaultId) public view returns (int128) {
        DataTypes.Vault memory vault_ = vaults[vaultId];
        require (vault_.owner != address(0), "Vault not found");                            // The vault existing is enough to be certain that the oracle exists.
        DataTypes.Balances memory balances_ = balances[vaultId];
        DataTypes.Series memory series_ = series[vault_.seriesId];

        return _level(vault_, balances_, series_);
    }

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    function _level(
        DataTypes.Vault memory vault_,
        DataTypes.Balances memory balances_,
        DataTypes.Series memory series_
    )
        internal view
        returns (int128)
    {
        DataTypes.SpotOracle memory spotOracle_ = spotOracles[series_.baseId][vault_.ilkId];
        uint128 spot = spotOracle_.oracle.spot();
        uint128 ratio = spotOracle_.ratio;

        if (uint32(block.timestamp) >= series_.maturity) {
            IOracle rateOracle = rateOracles[series_.baseId];
            uint128 accrual = rateOracle.accrual(series_.maturity);
            return balances_.ink.dmul(spot).i128() - balances_.art.dmul(accrual).dmul(ratio).i128();
        }

        return balances_.ink.dmul(spot).i128() - balances_.art.dmul(ratio).i128();
    }
}