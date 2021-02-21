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

    event VaultBuilt(bytes12 indexed vaultId, address indexed owner, bytes6 indexed seriesId, bytes6 ilkId);
    event VaultDestroyed(bytes12 indexed vaultId);
    event VaultTransfer(bytes12 indexed vaultId, address indexed receiver);

    event VaultFrobbed(bytes12 indexed vaultId, bytes6 indexed seriesId, bytes6 indexed ilkId, int128 ink, int128 art);

    mapping (bytes6 => IERC20)                      public assets;          // Underlyings and collaterals available in Vat. 12 bytes still free.
    mapping (bytes6 => mapping(bytes6 => uint128))  public debt;            // [baseId][ilkId] Sum of debt per collateral and underlying across all vaults
    mapping (bytes6 => DataTypes.Series)            public series;          // Series available in Vat. We can possibly use a bytes6 (3e14 possible series).
    mapping (bytes6 => mapping(bytes6 => bool))     public collaterals;     // [seriesId][assetId] Assets that are approved as collateral for a series

    mapping (bytes6 => address)                     chiOracles;             // Chi (savings rate) accruals oracle for the underlying
    mapping (bytes6 => address)                     rateOracles;            // Rate (borrowing rate) accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => address))  spotOracles;            // [assetId][assetId] Spot price oracles

    // ==== Vault ordering ====

    mapping (bytes12 => DataTypes.Vault)            public vaults;          // An user can own one or more Vaults, each one with a bytes12 identifier
    mapping (bytes12 => DataTypes.Balances)         public vaultBalances;   // Both debt and assets

    // ==== Vault timestamping ====
    mapping (bytes12 => uint32)                     timestamps;             // If grater than zero, time that a vault was timestamped. Used for liquidation.

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
        assetExists(baseId)                                              // 1 SLOAD
    {
        require (fyToken != IFYToken(address(0)), "Vat: Series need a fyToken");
        require (series[seriesId].fyToken == IFYToken(address(0)), "Vat: Id already used");
        series[seriesId] = DataTypes.Series({
            fyToken: fyToken,
            maturity: fyToken.maturity(),
            baseId: baseId
        });                                                             // 1 SSTORE
        emit SeriesAdded(seriesId, baseId, address(fyToken));
    }

    // TODO: function to allow an asset as collateral for a series

    /// @dev Ensure a asset exists        
    modifier assetExists(bytes6 assetId) {
        require (assets[assetId] != IERC20(address(0)), "Vat: Asset not found");
        _;
    }

    /// @dev Ensure a series exists        
    modifier seriesExists(bytes6 seriesId) {
        require (series[seriesId].fyToken != IFYToken(address(0)), "Vat: Series not found");
        _;
    }
    // function addOracle(IERC20 asset, IERC20 asset, IOracle oracle) external;

    // ==== Vault management ====

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(bytes6 seriesId, bytes6 ilkId)
        public
        seriesExists(seriesId)                                          // 1 SLOAD
        assetExists(ilkId)                                                // 1 SLOAD
        // TODO: validIlk(seriesId, ilkId) that checks that collaterals[seriesId][ilkId] == true
        returns (bytes12 vaultId)
    {
        vaultId = bytes12(keccak256(abi.encodePacked(msg.sender, block.timestamp)));               // Check (vaults[id].owner == address(0)), and increase the salt until a free vault id is found. 1 SLOAD per check.
        vaults[vaultId] = DataTypes.Vault({
            owner: msg.sender,
            seriesId: seriesId,
            ilkId: ilkId
        });                                                             // 1 SSTORE

        emit VaultBuilt(vaultId, msg.sender, seriesId, ilkId);
    }

    /// @dev Ensure a vault exists        
    modifier vaultExists(bytes12 vaultId) {
        require (vaults[vaultId].owner != address(0), "Vat: Vault not found");
        _;
    }

    /// @dev Ensure a function is only called by the vault owner. Already ensures the vault exists.       
    modifier vaultOwner(bytes12 vaultId) {
        require (vaults[vaultId].owner == msg.sender, "Vat: Only vault owner");
        _;
    }

    /* function emptyBalances(bytes12 vaultId) internal view returns (bool) {
        DataTypes.Balances memory balances = vaultBalances[vaultId];
        return balances.art == 0 && balances.ink == 0;
    } */

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId)
        public
        vaultOwner(vaultId)                                             // 1 SLOAD
    {
        // require (emptyBalances(vaultId), "Destroy only empty vaults");  // 1 SLOAD
        // delete timestamps[vaultId];                                     // 1 SSTORE REFUND
        delete vaults[vaultId];                                         // 1 SSTORE REFUND
        emit VaultDestroyed(vaultId);
    }

    // Change a vault series and/or collateral types.
    // We can change the series if there is no debt, or assets if there are no assets
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    /* function __tweak(bytes12 vaultId, bytes6 seriesId, bytes6 assetId)
        internal
    {
        Balances memory _balances = balances[vaultId];                  // 1 SLOAD
        Vault memory _vault = vaults[vaultId];                          // 1 SLOAD
        if (seriesId != bytes6(0)) {
            require (balances.art == 0, "Tweak only unused series");
            _vault.seriesId = seriesId;
        }
        if (assetId != bytes6(0)) {                                       // If a new asset was provided
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

        if (ink != 0) {
            _balances.ink = _balances.ink.add(ink);
        }

        if (art != 0) {
            debt[_series.baseId][_vault.ilkId] = debt[_series.baseId][_vault.ilkId].add(art); // 1 SSTORE. TODO: Test.
            _balances.art = _balances.art.add(art);                     // 1 SSTORE
        }
        vaultBalances[vaultId] = _balances;                             // 1 SSTORE

        emit VaultFrobbed(vaultId, _vault.seriesId, _vault.ilkId, ink, art);
        return _balances;
    }

    // ---- Restricted processes ----
    // Usable only by a authorized modules that won't cheat on Vat.

    // Change series and debt of a vault.
    // The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    /* function _roll(bytes12 vaultId, bytes6 seriesId, uint128 art)
        public
        auth
        vaultExists(vaultId)                                            // 1 SLOAD
    {
        balances[from].debt = 0;                                        // See two lines below
        __tweak(vaultId, series, 0);                                    // Cost of `__tweak`
        balances[from].debt = art;                                      // 1 SSTORE
        require(level(vaultId) >= 0, "Undercollateralized");            // Cost of `level`
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

    // Manipulate a vault without collateralization checks.
    // To be used for liquidation engines.
    // TODO: __frob underlying from and collateral to users
    function _frob(bytes12 vaultId, int128 ink, int128 art)
        public
        // auth                                                            // 1 SLOAD
        vaultExists(vaultId)                                            // 1 SLOAD
        returns (DataTypes.Balances memory balances)
    {
        balances = __frob(vaultId, ink, art);                             // Cost of `__frob`
        // if (balances.art > 0 && (ink < 0 || art > 0)) require(level(vaultId) >= 0, "Undercollateralized");  // Cost of `level`
        return balances;
    }

    // ---- Public processes ----

    // Give a vault to another user.
    function give(bytes12 vaultId, address user)
        public
        vaultOwner(vaultId)                                             // 1 SLOAD
    {
        __give(vaultId, user);                                          // Cost of `__give`
    }

    // Move collateral between vaults.
    /* function flux(bytes12 from, bytes12 to, uint128 ink)
        public
        vaultOwner(from)                                                // 1 SLOAD
        vaultExists(to)                                                 // 1 SLOAD
        returns (bytes32, bytes32)
    {
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