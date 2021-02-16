// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
// import "./interfaces/IOracle.sol";
// import "./libraries/IlksPacking.sol";
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./interfaces/IFYToken.sol";
import "./libraries/DataTypes.sol";


contract Vat {
    // using IlksPacking for bytes1;

    event VaultBuilt(bytes12 indexed id);
    event BaseAdded(bytes6 indexed id, address indexed base);
    event SeriesAdded(bytes6 indexed id, bytes6 indexed base, address indexed fyToken);

    mapping (bytes6 => IERC20)               public bases;              // Underlyings available in Vat. 12 bytes still free.
    mapping (bytes6 => DataTypes.Series)     public series;             // Series available in Vat. We can possibly use a bytes6 (3e14 possible series).

    /*
    mapping (bytes6 => address)                     ilks;               // Collaterals available in Vat. 12 bytes still free.
    mapping (bytes6 => address)                     joins;              // Join contracts available. 12 bytes still free.

    mapping (bytes6 => address)                     chiOracles;         // Chi (savings rate) accruals oracle for the underlying
    mapping (bytes6 => address)                     rateOracles;        // Rate (borrowing rate) accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => address))  spotOracles;        // [base][ilk] Spot price oracles

    // ==== Vault ordering ====
    */

    mapping (bytes12 => DataTypes.Vault)     public vaults;             // An user can own one or more Vaults, each one with a bytes12 identifier
    /*
    mapping (bytes12 => Ilks)                       vaultIlks;          // Collaterals are identified by just 6 bytes, then in 32 bytes (one SSTORE) we can have an array of 5 collateral types to allow multi-collateral vaults. 
    mapping (bytes12 => Balances)                   vaultBalances;      // Both debt and assets. The debt and the amount held for the first collateral share a word.

    // ==== Vault timestamping ====
    mapping (bytes12 => uint32)                     timestamps;         // If grater than zero, time that a vault was timestamped. Used for liquidation.
    */

    // ==== Administration ====
    /// @dev Add a new base
    function addBase(bytes6 id, IERC20 base) external /*auth*/ {
        require (bases[id] == IERC20(address(0)), "Vat: Id already used");
        bases[id] = base;
        emit BaseAdded(id, address(base));
    }                                     // Also known as underlying

    /// @dev Add a new series
    function addSeries(bytes6 id, bytes6 base, IFYToken fyToken, uint32 maturity) external /*auth*/ {
        require (series[id].fyToken == IFYToken(address(0)), "Vat: Id already used");
        require (bases[base] != IERC20(address(0)), "Vat: Base not present");
        series[id] = DataTypes.Series({
            fyToken: fyToken,
            maturity: maturity,
            base: base
        });                                                           // 1 SSTORE
        emit SeriesAdded(id, base, address(fyToken));
    }

    /*
    function addIlk(bytes6 id, address ilk) external;                            // Also known as collateral
    function addOracle(IERC20 base, IERC20 ilk, IOracle oracle) external;

    // ==== Vault management ====
    */

    /// @dev Create a new vault, linked to a series (and therefore underlying) and up to 5 collateral types
    function build(bytes6 series, bytes32 ilks)
        public
        returns (bytes12 id)
    {
        // require (validSeries(series), "Invalid series");               // 1 SLOAD
        bytes12 id = bytes12(keccak256(abi.encodePacked(msg.sender, block.timestamp)));               // Check (vaults[id].owner == address(0)), and increase the salt until a free vault id is found. 1 SLOAD per check.
        vaults[id] = DataTypes.Vault({
            owner: msg.sender,
            series: series
        });                                                           // 1 SSTORE

        /*
        require (validIlks(ilks), "Invalid collaterals");              // C SLOAD.
        Ilks memory _ilks = Ilks({
            ids: ilks.slice(0, 30),
            length: ilks.slice(30, 32)
        });
        ilks[id] = _ilks;                                              // 1 SSTORE
        */

        emit VaultBuilt(id);
    }

    /*
    // Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vault)
        public
    {
        require (validVault(vault), "Invalid vault");                  // 1 SLOAD
        require (vaults[vault].owner == msg.sender, "Only owner");     // 1 SLOAD
        Balances memory _balances = balances[vault];                   // 3 SLOAD
        require (_balances.debt == 0, "Destroy only empty vaults");
        Ilks memory _ilks = ilks[vault];                               // 1 SLOAD
        for (uint256 ilk = 0; ilk < _ilks.length; ilk++) {
            require (balances.assets[_ilks.ids[ilk]] == 0, "Destroy only empty vaults");
        }
        delete ilks[vault];                                            // 1 SSTORE REFUND
        delete vaults[vault];                                          // 1 SSTORE REFUND
        delete timestamps[vault];                                      // 1 SSTORE REFUND
    }

    // Change a vault series and/or collateral types.
    // We can change the series if there is no debt, or ilks if there are no assets
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    function __tweak(bytes12 vault, bytes6 series, Ilks memory ilks)
        internal
    {
        Balances memory _balances = balances[vault];                   // 3 SLOAD. If the ilks are loaded before maybe we can do less SLOAD
        if (series > 0) {
            require (balances.debt == 0, "Tweak only unused series");
            vaults[vault].series = series;                              // 1 SSTORE 
        }
        if (ilks > 0) {                                                // If a new set of ilks was provided
            Ilks memory _ilks = ilks[vault];                           // 1 SLOAD
            for (uint256 ilk = 0; ilk < _ilks.length; ilk++) {                           // Loop on the provided ilks by index
                require (balances.assets[ilk] == 0, "Tweak only unused assets");  // Check on the parameter ilks that the balance at that index is 0
                _ilks[ilk] = ilks[ilk];                                // Swap the ilk identifier
            }
            vaultIlks[vault] = _ilks ;                                    // 1 SSTORE
        }
    }

    // Transfer a vault to another user.
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    function __give(bytes12 vault, address user)
        internal
    {
        vaults[vault].owner = user;                                    // 1 SSTORE
    }

    // ==== Asset and debt management ====

    // Move collateral between vaults.
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    function __flux(bytes12 from, bytes12 to, Ilks memory ilks, uint128[] memory inks)
        internal
    {
        Balances memory _balancesFrom = balances[from];                // 3 SLOAD
        Balances memory _balancesTo = balances[to];                    // 3 SLOAD
        for (uint256 ilk = 0; ilk < _ilks.length; ilk++) {
            _balancesFrom.assets[ilk] -= inks[ilk];
            _balancesTo.assets[ilk] += inks[ilk];
        }
        balances[from] = _balancesFrom;                                // (C+1)/2 SSTORE
        balances[to] = _balancesTo;                                    // (C+1)/2 SSTORE
    }

    // Add collateral and borrow from vault, pull ilks from and push borrowed asset to user
    // Or, repay to vault and remove collateral, pull borrowed asset from and push ilks to user
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    function __frob(bytes12 vault, Ilks memory ilks, int128[] memory inks, int128 art)
        internal returns (Balances)
    {
        Balances memory _balances = balances[vault];                   // 3 SLOAD
        for (uint256 ilk = 0; ilk < _ilks.length; ilk++) {
            _balances.assets[ilk] += joins[ilk].join(inks[ilk]);       // Cost of `join`. `join` with a negative value means `exit`.. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `Join` interface.
        }
        
        if (art != 0) {
            _balances.debt += art;
            Series memory _series = series[vault];                     // 1 SLOAD
            if (art > 0) {
                require(block.timestamp <= _series.maturity, "Mature");
                IFYToken(_series.fyToken).mint(msg.sender, art);       // 1 CALL(40) + fyToken.mint. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `FYDai` interface.
            } else {
                IFYToken(_series.fyToken).burn(msg.sender, art);       // 1 CALL(40) + fyToken.burn. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `FYDai` interface.
            }
        }
        balances[id] = _balances;                                      // (C+1)/2 SSTORE. Refactor for Checks-Effects-Interactions

        return _balances;
    }
    
    // Repay vault debt using underlying token, pulled from user. Collateral is returned to user
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    // TODO: `__frob` with recipient
    function __close(bytes12 vault, Ilks memory ilks, int128[] memory inks, uint128 repay) 
        internal returns (bytes32[3])
    {
        bytes6 base = series[vault].base;                              // 1 SLOAD
        joins[base].join(repay);                                       // Cost of `join`
        uint128 debt = repay / rateOracles[base].spot();                // 1 SLOAD + `spot`
        return __frob(vault, ilks, inks, -int128(debt));                // Cost of `__frob`
    }

    // ---- Restricted processes ----
    // Usable only by a authorized modules that won't cheat on Vat.

    // Change series and debt of a vault.
    // The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    function _roll(bytes12 vault, bytes6 series, uint128 art)
        public
        auth                                                           // 1 SLOAD
    {
        require (validVault(vault), "Invalid vault");                  // 1 SLOAD
        balances[from].debt = 0;                                       // See two lines below
        __tweak(vault, series, []);                                    // Cost of `__tweak`
        balances[from].debt = art;                                     // 1 SSTORE
        require(level(vault) >= 0, "Undercollateralized");             // Cost of `level`
    }

    // Give a non-timestamped vault to the caller, and timestamp it.
    // To be used for liquidation engines.
    function _grab(bytes12 vault)
        public
        auth                                                           // 1 SLOAD
    {
        require (timestamps[vault] + 24*60*60 <= block.timestamp, "Timestamped"); // 1 SLOAD. Grabbing a vault protects it for a day from being grabbed by another liquidator.
        timestamps[vault] = block.timestamp;                           // 1 SSTORE
        __give(vault, msg.sender);                                     // Cost of `__give`
    }

    // Manipulate a vault without collateralization checks.
    // To be used for liquidation engines.
    // TODO: __frob underlying from and collateral to users
    function _frob(bytes12 vault, bytes1 ilks,  int128[] memory inks, int128 art)
        public
        auth                                                           // 1 SLOAD
        returns (bytes32[3])
    {
        require (validVault(vault), "Invalid vault");                  // 1 SLOAD
        Ilks memory selectedIlks = vaultIlks[vault].select(ilks);      // 1 SLOAD
        return __frob(vault, _ilks, inks, art);                        // Cost of `__frob`
    }

    // ---- Public processes ----

    // Give a vault to another user.
    function give(bytes12 vault, address user)
        public
    {
        require (validVault(vault), "Invalid vault");                  // 1 SLOAD
        require (vaults[vault].owner == msg.sender, "Only owner");     // 1 SLOAD
        __give(vault, user);                                           // Cost of `__give`
    }

    // Move collateral between vaults.
    function flux(bytes12 from, bytes12 to, bytes1 ilks, uint128[] memory inks)
        internal
        returns (bytes32[3], bytes32[3])
    {
        require (validVault(from), "Invalid origin");                  // 1 SLOAD
        require (vaults[from].owner == msg.sender, "Only owner");      // 1 SLOAD
        require (validVault(to), "Invalid recipient");                 // 1 SLOAD
        Ilks memory selectedIlks = vaultIlks[vault].select(ilks);      // 1 SLOAD
        bool check;
        for (uint256 ilk = 0; ilk < selectedIlks.length; ilk++) {
            check = check || inks[ilk] < 0;
        }
        Balances memory _balancesFrom;
        Balances memory _balancesTo;
        (_balancesFrom, _balancesTo) = __flux(vault, selectedIlks, inks, art);// Cost of `__flux`
        if (check) require(level(vault) >= 0, "Undercollateralized");  // Cost of `level`
        return (_balancesFrom, _balancesTo);
    }

    // Add collateral and borrow from vault, pull ilks from and push borrowed asset to user
    // Or, repay to vault and remove collateral, pull borrowed asset from and push ilks to user
    // Checks the vault is valid, and collateralization levels at the end.
    function frob(bytes12 vault, bytes1 ilks,  int128[] memory inks, int128 art)
        public returns (bytes32[3])
    {
        require (validVault(vault), "Invalid vault");                  // 1 SLOAD
        require (vaults[vault].owner == msg.sender, "Only owner");     // 1 SLOAD
        Ilks memory selectedIlks = vaultIlks[vault].select(ilks);      // 1 SLOAD
        bool check = art < 0;
        for (uint256 ilk = 0; ilk < selectedIlks.length; ilk++) {
            check = check || inks[ilk] < 0;
        }
        Balances memory _balances = __frob(vault, selectedIlks, inks, art);   // Cost of `__frob`
        if (check) require(level(vault) >= 0, "Undercollateralized");  // Cost of `level`
        return balances;
    }

    // Repay vault debt using underlying token, pulled from user. Collateral is returned to caller
    function close(bytes12 vault, bytes1 ilks, int128[] memory inks, uint128 repay) 
        public returns (bytes32[3])
    {
        require (validVault(vault), "Invalid vault");                  // 1 SLOAD
        require (vaults[vault].owner == msg.sender, "Only owner");     // 1 SLOAD
        Ilks memory selectedIlks = vaultIlks[vault].select(ilks);      // 1 SLOAD
        return __close(vault, selectedIlks, inks, repay);                      // Cost of `__close`
    }

    // ==== Accounting ====

    // Return the vault debt in underlying terms
    function dues(bytes12 vault) public view returns (uint128 uart) {
        Series _series = series[vault];                                // 1 SLOAD
        IFYToken fyToken = _series.fyToken;
        if (block.timestamp >= _series.maturity) {
            IOracle oracle = rateOracles[_series.base];                // 1 SLOAD
            uart = balances[vault].debt * oracle.accrual(maturity);    // 1 SLOAD + 1 Oracle Call
        } else {
            uart = balances[vault].debt;                               // 1 SLOAD
        }
    }

    // Return the capacity of the vault to borrow underlying based on the ilks held
    function value(bytes12 vault) public view returns (uint128 uart) {
        Ilks memory _ilks = ilks[vault];                               // 1 SLOAD
        Balances memory _balances = balances[vault];                   // 3 SLOAD. Maybe we can load less if there are less items in ilks
        bytes6 _base = series[vault].base;                             // 1 SLOAD
        for (uint256 ilk = 0; ilk < _ilks.length; ilk++) {                                                 // * C
            IOracle oracle = spotOracles[_base][ilk];                  // 1 SLOAD
            uart += _balances[ilk] * oracle.spot();                    // 1 Oracle Call | Divided by collateralization ratio
        }
    }

    // Return the collateralization level of a vault. It will be negative if undercollateralized.
    function level(bytes12 vault) public view returns (int128) {              // Cost of `value` + `dues`
        return value(vault) - dues(vault);
    }
    */
}