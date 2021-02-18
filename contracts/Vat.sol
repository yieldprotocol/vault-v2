// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./interfaces/IFYToken.sol";
// import "./interfaces/IOracle.sol";
import "./libraries/DataTypes.sol";


contract Vat {

    event BaseAdded(bytes6 indexed baseId, address indexed base);
    event IlkAdded(bytes6 indexed ilkId, address indexed ilk);
    event SeriesAdded(bytes6 indexed seriesId, bytes6 indexed baseId, address indexed fyToken);
    event VaultBuilt(bytes12 indexed vaultId, address indexed owner, bytes6 indexed seriesId, bytes6 ilkId);
    event VaultDestroyed(bytes12 indexed vaultId);
    event VaultTransfer(bytes12 indexed vaultId, address indexed receiver);

    mapping (bytes6 => IERC20)               public bases;              // Underlyings available in Vat. 12 bytes still free.
    mapping (bytes6 => IERC20)               public ilks;               // Collaterals available in Vat. 12 bytes still free (maybe for ceiling)
    mapping (bytes6 => uint256)              public ilkDebt;            // Collateral locked in debt across all vaults
    mapping (bytes6 => DataTypes.Series)     public series;             // Series available in Vat. We can possibly use a bytes6 (3e14 possible series).

    mapping (bytes6 => address)                     joins;              // Join contracts available. 12 bytes still free.

    mapping (bytes6 => address)                     chiOracles;         // Chi (savings rate) accruals oracle for the underlying
    mapping (bytes6 => address)                     rateOracles;        // Rate (borrowing rate) accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => address))  spotOracles;        // [base][ilk] Spot price oracles

    // ==== Vault ordering ====

    mapping (bytes12 => DataTypes.Vault)     public vaults;             // An user can own one or more Vaults, each one with a bytes12 identifier
    mapping (bytes12 => DataTypes.Balances)  public vaultBalances;      // Both debt and assets

    // ==== Vault timestamping ====
    mapping (bytes12 => uint32)                     timestamps;         // If grater than zero, time that a vault was timestamped. Used for liquidation.

    // ==== Administration ====
    /// @dev Add a new base
    // TODO: Should we add a base Join now, before, or after?
    function addBase(bytes6 baseId, IERC20 base) external /*auth*/ {
        require (bases[baseId] == IERC20(address(0)), "Vat: Id already used");
        bases[baseId] = base;
        emit BaseAdded(baseId, address(base));
    }                                     // Also known as underlying

    function addIlk(bytes6 ilkId, IERC20 ilk)
        external
    {
        require (ilks[ilkId] == IERC20(address(0)), "Vat: Id already used");
        ilks[ilkId] = ilk;
        emit IlkAdded(ilkId, address(ilk));
    }                   // Also known as collateral

    /// @dev Add a new series
    // TODO: Should we add a fyToken Join now, before, or after?
    function addSeries(bytes6 seriesId, bytes6 baseId, IFYToken fyToken)
        external
        /*auth*/
        baseExists(baseId)                                              // 1 SLOAD
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

    /// @dev Ensure a base exists        
    modifier baseExists(bytes6 baseId) {
        require (bases[baseId] != IERC20(address(0)), "Vat: Base not found");
        _;
    }

    /// @dev Ensure an ilk exists        
    modifier ilkExists(bytes6 ilkId) {
        require (ilks[ilkId] != IERC20(address(0)), "Vat: Ilk not found");
        _;
    }

    /// @dev Ensure a series exists        
    modifier seriesExists(bytes6 seriesId) {
        require (series[seriesId].fyToken != IFYToken(address(0)), "Vat: Series not found");
        _;
    }
    // function addOracle(IERC20 base, IERC20 ilk, IOracle oracle) external;

    // ==== Vault management ====

    /// @dev Create a new vault, linked to a series (and therefore underlying) and up to 5 collateral types
    function build(bytes6 seriesId, bytes6 ilkId)
        public
        seriesExists(seriesId)                                          // 1 SLOAD
        ilkExists(ilkId)                                                // 1 SLOAD
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
    // We can change the series if there is no debt, or ilks if there are no assets
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    /* function __tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        internal
    {
        Balances memory _balances = balances[vaultId];                  // 1 SLOAD
        Vault memory _vault = vaults[vaultId];                          // 1 SLOAD
        if (seriesId != bytes6(0)) {
            require (balances.art == 0, "Tweak only unused series");
            _vault.seriesId = seriesId;
        }
        if (ilkId != bytes6(0)) {                                       // If a new ilk was provided
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
        require (vaults[from].ilk == vaults[to].ilk, "Vat: Different collateral"); // 2 SLOAD
        balances[from].assets -= ink;                                   // 1 SSTORE
        balances[to].assets += ink;                                     // 1 SSTORE
    } */

    // Add collateral and borrow from vault, pull ilks from and push borrowed asset to user
    // Or, repay to vault and remove collateral, pull borrowed asset from and push ilks to user
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    /* function __frob(bytes12 vaultId, int128 ink, int128 art)
        internal returns (Balances)
    {
        Vault memory _vault = vaults[vaultId];                          // 1 SLOAD
        Balances memory _balances = balances[vaultId];                  // 1 SLOAD

        if (ink != 0) {
            _balances.assets += joins[_vault.ilkId].join(ink);          // Cost of `join`. `join` with a negative value means `exit`.. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `Join` interface.
        }

        if (art != 0) {
            _balances.debt += art;
            Series memory _series = series[_vault.seriesId];            // 1 SLOAD
            if (art > 0) {
                require(block.timestamp <= _series.maturity, "Mature");
                IFYToken(_series.fyToken).mint(msg.sender, art);        // 1 CALL(40) + fyToken.mint. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `FYDai` interface.
            } else {
                IFYToken(_series.fyToken).burn(msg.sender, art);        // 1 CALL(40) + fyToken.burn. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `FYDai` interface.
            }

            int128 _ilkDebt = art / spotOracles[_series.baseId][ilk];   // 1 Oracle Call | Divided by collateralization ratio | Repeated with `value` when checking collateralization levels
            ilkDebt[_vault.ilkId] += _ilkDebt;                          // 1 SSTORE
        }
        balances[vaultId] = _balances;                                  // 1 SSTORE. Refactor for Checks-Effects-Interactions

        return _balances;
    } */
    
    // Repay vault debt using underlying token, pulled from user. Collateral is returned to user
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    // TODO: `__frob` with recipient
    /* function __close(bytes12 vault, int128 ink, uint128 repay) 
        internal returns (bytes32[3])
    {
        bytes6 base = series[vaultId].baseId;                           // 1 SLOAD
        joins[base].join(repay);                                        // Cost of `join`
        uint128 debt = repay / rateOracles[base].spot();                // 1 SLOAD + `spot`
        return __frob(vaultId, ink, -int128(debt));                     // Cost of `__frob`
    } */

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
    /* function _frob(bytes12 vaultId, int128 ink, int128 art)
        public
        auth                                                            // 1 SLOAD
        vaultExists(vaultId)                                            // 1 SLOAD
        returns (bytes32)
    {
        return __frob(vault, ink, art);                                 // Cost of `__frob`
    } */

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

    // Add collateral and borrow from vault, pull ilks from and push borrowed asset to user
    // Or, repay to vault and remove collateral, pull borrowed asset from and push ilks to user
    // Checks the vault is valid, and collateralization levels at the end.
    /* function frob(bytes12 vaultId, int128 ink, int128 art)
        public
        vaultOwner(vaultId)                                             // 1 SLOAD
        returns (bytes32)
    {
        Balances memory _balances = __frob(vaultId, ink, art);          // Cost of `__frob`
        if (_balances.art > 0) require(level(vaultId) >= 0, "Undercollateralized");  // Cost of `level`
        return balances;
    } */

    // Repay vault debt using underlying token, pulled from user. Collateral is returned to caller
    /* function close(bytes12 vaultId, uint128 ink, uint128 repay)
        public
        vaultOwner(vaultId)                                             // 1 SLOAD
        returns (bytes32)
    {
        return __close(vaultId, int128(ink), repay);                    // Cost of `__close`
    } */

    // ==== Accounting ====

    // Return the vault debt in underlying terms
    /* function dues(bytes12 vaultId) public view returns (uint128 uart) {
        Series _series = series[vaultId];                               // 1 SLOAD
        IFYToken fyToken = _series.fyToken;
        if (block.timestamp >= _series.maturity) {
            IOracle oracle = rateOracles[_series.base];                 // 1 SLOAD
            uart = balances[vaultId].art * oracle.accrual(maturity);    // 1 SLOAD + 1 Oracle Call
        } else {
            uart = balances[vaultId].art;                               // 1 SLOAD
        }
    } */

    // Return the capacity of the vault to borrow underlying based on the ilks held
    /* function value(bytes12 vaultId) public view returns (uint128 uart) {
        bytes6 ilk = vaults[vaultId].ilk;                               // 1 SLOAD
        Balances memory _balances = balances[vaultId];                  // 1 SLOAD
        bytes6 _base = series[vaultId].base;                            // 1 SLOAD
        IOracle oracle = spotOracles[_base][ilk];                       // 1 SLOAD
        uart += _balances.ink * oracle.spot();                          // 1 Oracle Call | Divided by collateralization ratio
    } */

    // Return the collateralization level of a vault. It will be negative if undercollateralized.
    /* function level(bytes12 vaultId) public view returns (int128) {      // Cost of `value` + `dues`
        return value(vaultId) - dues(vaultId);
    } */
}