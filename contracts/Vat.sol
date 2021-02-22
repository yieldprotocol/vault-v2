// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./interfaces/IFYToken.sol";
import "./interfaces/IJoin.sol";
// import "./interfaces/IOracle.sol";
import "./libraries/DataTypes.sol";


library Math {
    /// @dev Add a number (which might be negative) to a positive, and revert if the result is negative.
    function add(uint128 x, int128 y) internal pure returns (uint128 z) {
        require (y > 0 || x >= uint128(-y), "Math: Negative result");
        z = y > 0 ? x + uint128(y) : x - uint128(-y);
    }
}

contract Vat {
    using Math for uint128;

    event AssetAdded(bytes6 indexed assetId, address indexed asset);
    event SeriesAdded(bytes6 indexed seriesId, bytes6 indexed baseId, address indexed fyToken);
    event IlkAdded(bytes6 indexed seriesId, bytes6 indexed ilkId);
    event SpotOracleAdded(bytes6 indexed baseId, bytes6 indexed ilkId, address indexed oracle);
    event MaxDebtSet(bytes6 indexed baseId, bytes6 indexed ilkId, uint128 max);

    event VaultBuilt(bytes12 indexed vaultId, address indexed owner, bytes6 indexed seriesId, bytes6 ilkId);
    event VaultDestroyed(bytes12 indexed vaultId);
    event VaultTransfer(bytes12 indexed vaultId, address indexed receiver);

    event VaultFrobbed(bytes12 indexed vaultId, bytes6 indexed seriesId, bytes6 indexed ilkId, int128 ink, int128 art);

    mapping (bytes6 => IERC20)                              public assets;      // Underlyings and collaterals available in Vat. 12 bytes still free.
    mapping (bytes6 => mapping(bytes6 => DataTypes.Debt))   public debt;        // [baseId][ilkId] Max and sum of debt per underlying and collateral.
    mapping (bytes6 => DataTypes.Series)                    public series;      // Series available in Vat. We can possibly use a bytes6 (3e14 possible series).
    mapping (bytes6 => mapping(bytes6 => bool))             public ilks;        // [seriesId][assetId] Assets that are approved as collateral for a series

    mapping (bytes6 => IOracle)                             public chiOracles;  // Chi (savings rate) accruals oracle for the underlying
    mapping (bytes6 => IOracle)                             public rateOracles; // Rate (borrowing rate) accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => IOracle))          public spotOracles; // [assetId][assetId] Spot price oracles

    // ==== Vault ordering ====

    mapping (bytes12 => DataTypes.Vault)                    public vaults;      // An user can own one or more Vaults, each one with a bytes12 identifier
    mapping (bytes12 => DataTypes.Balances)                 public vaultBalances; // Both debt and assets

    // ==== Vault timestamping ====
    mapping (bytes12 => uint32)                             public timestamps;  // If grater than zero, time that a vault was timestamped. Used for liquidation.

    // ==== Administration ====

    /// @dev Add a new Asset.
    function addAsset(bytes6 assetId, IERC20 asset)
        external
    {
        require (assets[assetId] == IERC20(address(0)), "Vat: Id already used");
        assets[assetId] = asset;
        emit AssetAdded(assetId, address(asset));
    }                   // Also known as collateral

    /// @dev Add a new series
    function addSeries(bytes6 seriesId, bytes6 baseId, IFYToken fyToken)
        external
        /*auth*/
    {
        require (assets[baseId] != IERC20(address(0)), "Vat: Asset not found"); // 1 SLOAD
        require (fyToken != IFYToken(address(0)), "Vat: Series need a fyToken");
        require (series[seriesId].fyToken == IFYToken(address(0)), "Vat: Id already used");
        series[seriesId] = DataTypes.Series({
            fyToken: fyToken,
            maturity: fyToken.maturity(),
            baseId: baseId
        });                                                             // 1 SSTORE
        emit SeriesAdded(seriesId, baseId, address(fyToken));
    }

    /// @dev Add a spot oracle
    function addSpotOracle(bytes6 baseId, bytes6 ilkId, IOracle oracle)
        external
    {
        require (assets[baseId] != IERC20(address(0)), "Vat: Asset not found"); // 1 SLOAD
        require (assets[ilkId] != IERC20(address(0)), "Vat: Asset not found"); // 1 SLOAD
        spotOracles[baseId][ilkId] = oracle;                                // 1 SSTORE. Allows to replace an existing oracle.
        emit SpotOracleAdded(baseId, ilkId, address(oracle));
    }

    /// @dev Add a new Ilk (approve an asset as collateral for a series).
    function addIlk(bytes6 seriesId, bytes6 ilkId)
        external
    {
        DataTypes.Series memory _series = series[seriesId];                                          // 1 SLOAD
        require (
            _series.fyToken != IFYToken(address(0)),
            "Vat: Series not found"
        );
        require (
            spotOracles[_series.baseId][ilkId] != IOracle(address(0)),                               // 1 SLOAD
            "Vat: Oracle not found"
        );
        ilks[seriesId][ilkId] = true;                                                                // 1 SSTORE
        emit IlkAdded(seriesId, ilkId);
    }

    /// @dev Add a new Ilk (approve an asset as collateral for a series).
    function setMaxDebt(bytes6 baseId, bytes6 ilkId, uint128 max)
        external
    {
        require (assets[baseId] != IERC20(address(0)), "Vat: Asset not found"); // 1 SLOAD
        require (assets[ilkId] != IERC20(address(0)), "Vat: Asset not found"); // 1 SLOAD
        debt[baseId][ilkId].max = max;                                   // 1 SSTORE
        emit MaxDebtSet(baseId, ilkId, max);
    }

    // ==== Vault management ====

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(bytes6 seriesId, bytes6 ilkId)
        public
        returns (bytes12 vaultId)
    {
        require (ilks[seriesId][ilkId] == true, "Vat: Ilk not added"); // 1 SLOAD
        vaultId = bytes12(keccak256(abi.encodePacked(msg.sender, block.timestamp)));               // Check (vaults[id].owner == address(0)), and increase the salt until a free vault id is found. 1 SLOAD per check.
        vaults[vaultId] = DataTypes.Vault({
            owner: msg.sender,
            seriesId: seriesId,
            ilkId: ilkId
        });                                                             // 1 SSTORE

        emit VaultBuilt(vaultId, msg.sender, seriesId, ilkId);
    }

    /* function emptyBalances(bytes12 vaultId) internal view returns (bool) {
        DataTypes.Balances memory balances = vaultBalances[vaultId];
        return balances.art == 0 && balances.ink == 0;
    } */

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId)
        public
    {
        require (vaults[vaultId].owner == msg.sender, "Vat: Only vault owner"); // 1 SLOAD
        // require (emptyBalances(vaultId), "Destroy only empty vaults");  // 1 SLOAD
        // delete timestamps[vaultId];                                     // 1 SSTORE REFUND
        delete vaults[vaultId];                                         // 1 SSTORE REFUND
        emit VaultDestroyed(vaultId);
    }

    // Change a vault series and/or collateral types.
    // We can change the series if there is no debt, or assets if there are no assets
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    /* function __tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        internal
    {
        require (ilks[seriesId][ilkId] == true, "Vat: Ilk not added"); // 1 SLOAD
        Balances memory _balances = balances[vaultId];                  // 1 SLOAD
        Vault memory _vault = vaults[vaultId];                          // 1 SLOAD
        if (seriesId != _vault.seriesId) {
            require (balances.art == 0, "Tweak only unused series");
            _vault.seriesId = seriesId;
        }
        if (ilkId != _vault.ilkId) {                                     // If a new asset was provided
            require (balances.ink == 0, "Tweak only unused assets");
            _vault.inkId = inkId;
        }
        vaults[vaultId] = _vault;                                       // 1 SSTORE
    } */

    /// @dev Transfer a vault to another user.
    /// Doesn't check inputs, or collateralization level. Do that in public functions.
    function __give(bytes12 vaultId, address receiver)
        internal
    {
        vaults[vaultId].owner = receiver;                               // 1 SSTORE
        emit VaultTransfer(vaultId, receiver);
    }

    // ==== Asset and debt management ====

    // Move collateral between vaults.
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    /* function __flux(bytes12 from, bytes12 to, uint128 ink)
        internal
    {
        require (vaults[from].asset == vaults[to].asset, "Vat: Different collateral"); // 2 SLOAD
        balances[from].assets -= ink;                                   // 1 SSTORE
        balances[to].assets += ink;                                     // 1 SSTORE
    } */

    // Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    // Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    // TODO: Extend to allow other accounts in `join`
    function __frob(bytes12 vaultId, int128 ink, int128 art)
        internal returns (DataTypes.Balances memory)
    {
        DataTypes.Vault memory _vault = vaults[vaultId];                // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];   // 1 SLOAD
        DataTypes.Series memory _series = series[_vault.seriesId];      // 1 SLOAD

        // For now, the collateralization checks are done outside to allow for underwater operation. That might change.
        if (ink != 0) {
            _balances.ink = _balances.ink.add(ink);
        }

        // TODO: Consider whether _roll should call __frob, or the next block be a private function.
        // Modify vault and global debt records. If debt increases, check global limit.
        if (art != 0) {
            DataTypes.Debt memory _debt = debt[_series.baseId][_vault.ilkId]; // 1 SLOAD
            if (art > 0) require (_debt.sum.add(art) <= _debt.max, "Vat: Max debt exceeded");
            _balances.art = _balances.art.add(art);
            _debt.sum = _debt.sum.add(art);
            debt[_series.baseId][_vault.ilkId] = _debt;                 // 1 SSTORE
        }
        vaultBalances[vaultId] = _balances;                             // 1 SSTORE

        emit VaultFrobbed(vaultId, _vault.seriesId, _vault.ilkId, ink, art);
        return _balances;
    }

    // ---- Restricted processes ----
    // Usable only by a authorized modules that won't cheat on Vat.

    // Change series and debt of a vault.
    // The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    // TODO: Should we allow changing the collateral at the same time?
    /* function _roll(bytes12 vaultId, bytes6 seriesId, int128 art)
        public
        auth
    {
        require (vaults[vaultId].owner != address(0), "Vat: Vault not found");  // 1 SLOAD
        DataTypes.Balances memory _balances = vaultBalances[vaultId];       // 1 SLOAD
        DataTypes.Series memory _series = series[vaultId];                  // 1 SLOAD
        
        delete vaultBalances[vaultId];                                      // -1 SSTORE
        __tweak(vaultId, seriesId, vaults[vaultId].ilkId);                  // 1 SLOAD + Cost of `__tweak`

        // Modify vault and global debt records. If debt increases, check global limit.
        if (art != 0) {
            DataTypes.Debt memory _debt = debt[_series.baseId][_vault.ilkId]; // 1 SLOAD
            if (art > 0) require (_debt.sum.add(art) <= _debt.max, "Vat: Max debt exceeded");
            _balances.art = _balances.art.add(art);
            _debt.sum = _debt.sum.add(art);
            debt[_series.baseId][_vault.ilkId] = _debt;                 // 1 SSTORE
        }
        vaultBalances[vaultId] = _balances;                                 // 1 SSTORE
        require(level(vaultId) >= 0, "Undercollateralized");                // Cost of `level`
    } */

    // Give a non-timestamped vault to the caller, and timestamp it.
    // To be used for liquidation engines.
    /* function _grab(bytes12 vaultId)
        public
        auth                                                            // 1 SLOAD
    {
        require (timestamps[vaultId] + 24*60*60 <= block.timestamp, "Timestamped"); // 1 SLOAD. Grabbing a vault protects it for a day from being grabbed by another liquidator.
        timestamps[vaultId] = block.timestamp;                          // 1 SSTORE
        __give(vaultId, msg.sender);                                    // Cost of `__give`
    } */

    /// @dev Manipulate a vault with collateralization checks.
    /// Available only to authenticated platform accounts.
    /// To be used by debt management contracts.
    function _frob(bytes12 vaultId, int128 ink, int128 art)
        public
        // auth                                                           // 1 SLOAD
        returns (DataTypes.Balances memory balances)
    {
        require (vaults[vaultId].owner != address(0), "Vat: Vault not found");  // 1 SLOAD
        balances = __frob(vaultId, ink, art);                             // Cost of `__frob`
        // if (balances.art > 0 && (ink < 0 || art > 0)) require(level(vaultId) >= 0, "Undercollateralized");  // Cost of `level`
        return balances;
    }

    // ---- Public processes ----

    // Give a vault to another user.
    function give(bytes12 vaultId, address user)
        public
    {
        require (vaults[vaultId].owner == msg.sender, "Vat: Only vault owner"); // 1 SLOAD
        __give(vaultId, user);                                          // Cost of `__give`
    }

    // Move collateral between vaults.
    /* function flux(bytes12 from, bytes12 to, uint128 ink)
        public
        returns (bytes32, bytes32)
    {
        require (vaults[from].owner == msg.sender, "Vat: Only vault owner");  // 1 SLOAD
        require (vaults[to].owner != address(0), "Vat: Vault not found");  // 1 SLOAD
        Balances memory _balancesFrom;
        Balances memory _balancesTo;
        (_balancesFrom, _balancesTo) = __flux(from, to, ink, art);      // Cost of `__flux`
        if (_balancesFrom.art > 0) require(level(from) >= 0, "Undercollateralized");  // Cost of `level`
        return (_balancesFrom, _balancesTo);
    } */

    // ==== Accounting ====

    // Return the vault debt in underlying terms
    /* function dues(bytes12 vaultId) public view returns (uint128 uart) {
        Series _series = series[vaultId];                               // 1 SLOAD
        IFYToken fyToken = _series.fyToken;
        if (block.timestamp >= _series.maturity) {
            IOracle oracle = rateOracles[_series.asset];                 // 1 SLOAD
            uart = balances[vaultId].art * oracle.accrual(maturity);    // 1 SLOAD + 1 Oracle Call
        } else {
            uart = balances[vaultId].art;                               // 1 SLOAD
        }
    } */

    // Return the capacity of the vault to borrow underlying assetd on the assets held
    /* function value(bytes12 vaultId) public view returns (uint128 uart) {
        bytes6 asset = vaults[vaultId].asset;                               // 1 SLOAD
        Balances memory _balances = balances[vaultId];                  // 1 SLOAD
        bytes6 _asset = series[vaultId].asset;                            // 1 SLOAD
        IOracle oracle = spotOracles[_asset][asset];                       // 1 SLOAD
        uart += _balances.ink * oracle.spot();                          // 1 Oracle Call | Divided by collateralization ratio
    } */

    // Return the collateralization level of a vault. It will be negative if undercollateralized.
    /* function level(bytes12 vaultId) public view returns (int128) {      // Cost of `value` + `dues`
        return value(vaultId) - dues(vaultId);
    } */
}