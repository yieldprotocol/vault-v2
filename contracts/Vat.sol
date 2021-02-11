// Token balances will be kept in the join, for flexibility in their management
contract TokenJoin {
    function join(address usr, uint wad)
    function exit(address usr, uint wad)

}

contract FYTokenJoin {
    function join(address usr, uint wad)
    function exit(address usr, uint wad)

}


contract Vat {
  
    // ---- Administration ----
    function addIlk(bytes6 id, address ilk)                            // Also known as collateral
    function addBase(address base)                                     // Also known as underlying
    function addSeries(bytes32 series, IERC20 base, IFYToken fyToken)
    function addOracle(IERC20 base, IERC20 ilk, IOracle oracle)

    mapping (bytes6 => address)                     chiOracles         // Chi accruals oracle for the underlying
    mapping (bytes6 => address)                     rateOracles        // Rate accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => address))  spotOracles        // [base][ilk] Spot oracles

    struct Series {
        address fyToken;
        uint32  maturity;
        bytes6  base;                                                  // We might want to make this an address, instead of an identifier
        // bytes2 free
    }

    mapping (bytes12 => Series)                     series             // Series available in Vat. We can possibly use a bytes6 (3e14 possible series).
    mapping (bytes6 => address)                     bases              // Underlyings available in Vat. 12 bytes still free.
    mapping (bytes6 => address)                     ilks               // Collaterals available in Vat. 12 bytes still free.

    // ---- Vault ordering ----
    struct Vault {
        address owner;
        bytes12 next;
        bytes12 series;                                                // address to pack next to it. Each vault is related to only one series, which also determines the underlying.
    }

    mapping (address => bytes12)                    first              // Pointer to the first vault in the user's list. We have 20 bytes here that we can still use.
    mapping (bytes12 => Vault)                      vaults             // With a vault identifier we can get both the owner and the next in the list. When giving a vault both are changed with 1 SSTORE.

    // ---- Vault composition ----
    struct Ilks {
        bytes6[5] ids;
        bytes2 length;
    }

    struct Balances {
        uint128 debt;
        uint128[5] assets;
    }

    // An user can own one or more Vaults, each one with a bytes12 identifier so that we can pack a singly linked list and a reverse search in a bytes32
    mapping (bytes12 => Ilks)                       vaultIlks   // Collaterals are identified by just 6 bytes, then in 32 bytes (one SSTORE) we can have an array of 5 collateral types to allow multi-collateral vaults. 
    mapping (bytes12 => Balances)                   vaultBalances      // Both debt and assets. The debt and the amount held for the first collateral share a word.

    // ---- Vault management ----
    // Create a new vault, linked to a series (and therefore underlying) and up to 6 collateral types
    // 2 SSTORE for series and up to 6 collateral types, plus 2 SSTORE for vault ownership.
    function build(bytes12 series, bytes32 ilks)
        public
        returns (bytes12 id)
    {
        require (validSeries(series), "Invalid series");               // 1 SLOAD.
        bytes12 _first = first[msg.sender];                            // 1 SLOAD. Use the id of the latest vault created by the user as salt.
        bytes12 id = keccak256(msg.sender + _first)-slice(0, 12);      // Check (vaults[id].owner == address(0)), and increase the salt until a free vault id is found. 1 SLOAD per check.
        Vault memory vault = ({
            owner: msg.sender;
            next: _first;
            series: series;
        });
        first[msg.sender] = id;                                        // 1 SSTORE. We insert the new vaults in the list head.
        vaults[id] = vault;                                            // 2 SSTORE. We can still store one more address for free.

        require (validIlks(ilks), "Invalid ilks");// C SLOAD.
        Ilks memory _ilks = ({
            ids: ilks.slice(0, 30);
            length: ilks.slice(30, 32);
        });
        ilks[id] = _ilks;                                              // 1 SSTORE
    }

    // Change a vault series and/or collateral types.
    // We can change the series if there is no debt, or ilks if there are no assets
    function __tweak(bytes12 vault, bytes12 series, bytes32 ilks)
        internal
    {
        require (validVault(vault), "Invalid vault");                             // 1 SLOAD
        require (validSeries(series), "Invalid series");                          // 1 SLOAD
        Balances memory _balances = balances[vault];                              // 1 SLOAD
        if (series > 0) {
            require (balances.debt == 0, "Tweak only unused series");
            vaults[vault].series = series                                         // 1 SSTORE 
        }
        if (ilks > 0) {                                                           // If a new set of ilks was provided
            Ilks memory _ilks = ilks[vault];                                      // 1 SLOAD
            for ilk in _ilks {                                                    // Loop on the provided ilks by index
                require (balances.assets[ilk] == 0, "Tweak only unused assets");  // Check on the vault ilks that the balance at that index is 0
                _ilks[ilk] = ilks[ilk];                                           // Swap the ilk identifier
            }
            balances[vault] = _balances;                                          // 1 SSTORE
        }
    }

    // Transfer vault to another user.
    function __give(bytes12 vault, address user)
        internal
    {
        Vault memory _vault = vaults[vault];                                          // 2 SLOAD. Split the list and series sections of Vault.
        bytes12 _previous = previous(vault);                                          // V * 2 SLOAD. Split the list and series sections of Vault.
        if (_previous == 0) { // Also consider next == 0
            first[_vault.owner] = _vault.next;                                        // 1 SSTORE
        } else {
            if (vaults[_previous].next != 0 && _vault.next != 0) {
                vaults[_previous].next = _vault.next;                                 // 1 SSTORE
            }
        }
        _vault.owner = user;
        _vault.next = first[user];
        vaults[vault] = _vault;                                                       // 1 SSTORE
        first[user] = vault;                                                          // 1 SSTORE
    }

    // Move collateral between vaults.
    function __flux(bytes12 from, bytes12 to, bytes32 ilks, uint128[] memory inks)
        internal
    {
        Balances memory _balancesFrom = balances[from];                               // 1 SLOAD
        Balances memory _balancesTo = balances[to];                                   // 1 SLOAD
        for each ilk in ilks {
            _balancesFrom.assets[ilk] -= inks[ilk];
            _balancesTo.assets[ilk] += inks[ilk];
        }
        balances[from] = _balancesFrom;                                               // (C+1)/2 SSTORE
        balances[to] = _balancesTo;                                                   // (C+1)/2 SSTORE
    }

    // Change series and debt of a vault.
    // Usable only by an authorized module that won't cheat on Vat. 
    // The module also needs to buy underlying in Pool2, and sell it in Pool1.
    function _roll(bytes12 vault, bytes6 series, uint128 art)
        public
        auth
    {
        require (validVault(vault), "Invalid vault");                                 // 1 SLOAD
        balances[from].debt = 0;                                                      // See two lines below
        __tweak(vault, series, []);                                                   // Cost of `__tweak`
        balances[from].debt = art;                                                    // 1 SSTORE
        require(level(vault) >= 0, "Undercollateralized");                            // Cost of `level`
    }

    // Add collateral and borrow from vault, pull ilks from and push borrowed asset to user
    // Repay to vault and remove collateral, pull borrowed asset from and push ilks to user
    // Doesn't check inputs, or collateralization level.
    function __frob(bytes12 vault, bytes6[] memory ilks, int128[] memory inks, int128 art)
        internal returns (bytes32[3])
    {
        Balances memory _balances = balances[vault];                                  // 1 SLOAD
        for each ilk in ilks {
            _balances.assets[ilk] += joins[ilk].join(inks[ilk]);                      // Cost of `join`. `join` with a negative value means `exit`
        }
        
        if (art != 0) {
            _balances.debt += art;
            Series memory _series = series[vault];                                    // 1 SLOAD
            if (art > 0) {
                require(block.timestamp <= _series.maturity, "Mature");
                IFYToken(_series.fyToken).mint(msg.sender, art);                      // 1 CALL(40) + fyToken.mint
            } else {
                IFYToken(_series.fyToken).burn(msg.sender, art);                      // 1 CALL(40) + fyToken.burn
            }
        }
        balances[id] = _balances;                                                     // (C+1)/2 SSTORE. Refactor for Checks-Effects-Interactions

        return _balances;
    }
    
    // Add collateral and borrow from vault, pull ilks from and push borrowed asset to user
    // Repay to vault and remove collateral, pull borrowed asset from and push ilks to user
    // Checks the vault is valid, and collateralization levels at the end.
    function frob(bytes12 vault, bytes1 ilks,  int128[] memory inks, int128 art)
        public returns (bytes32[3])
    {
        require (validVault(vault), "Invalid vault");                                 // 1 SLOAD
        bytes6[] memory _ilks = unpackIlks(vault, ilks);                              // 1 SLOAD
        bool check = art < 0;
        for each ilk {
            check = check || inks[ilk] < 0;
        }
        Balances memory _balances = __frob(vault, _ilks, inks, art);                  // Cost of `__frob`
        if (check) require(level(vault) >= 0, "Undercollateralized");                 // Cost of `level`
        return balances;
    }

    // Repay vault debt using underlying token, pulled from user. Collateral is returned to user
    function __close(bytes12 vault, bytes6[] memory ilks, int128[] memory inks, uint128 repay) 
        internal returns (bytes32[3])
    {
        bytes6 base = series[vault].base;                                             // 1 SLOAD
        joins[base].join(repay);                                                      // Cost of `join`
        uint128 debt = repay / rateOracles[base].spot()                               // 1 SLOAD + `spot`
        return __frob(vault, ilks, inks, -int128(debt))                               // Cost of `__frob`
    }

    // ---- Accounting ----

    // Return the vault debt in underlying terms
    function dues(bytes12 vault) view returns (uint128 uart) {
        Series _series = series[vault];                                   // 1 SLOAD
        IFYToken fyToken = _series.fyToken;
        if (block.timestamp >= _series.maturity) {
            IOracle oracle = rateOracles[_series.base];                   // 1 SLOAD
            uart = balances[vault].debt * oracle.accrual(maturity);       // 1 SLOAD + 1 Oracle Call
        } else {
            uart = balances[vault].debt;                                  // 1 SLOAD
        }
    }

    // Return the capacity of the vault to borrow underlying based on the ilks held
    function value(bytes12 vault) view returns (uint128 uart) {
        Ilks memory _ilks = ilks[vault];                                  // 1 SLOAD
        Balances memory _balances = balances[vault];                      // 1 SLOAD
        bytes6 _base = series[vault].base;                            // 1 SLOAD
        for each ilk {                                                    // * C
            IOracle oracle = spotOracles[_base][ilk];                     // 1 SLOAD
            uart += _balances[ilk] * oracle.spot();                       // 1 Oracle Call | Divided by collateralization ratio
        }
    }

    // Return the collateralization level of a vault. It will be negative if undercollateralized.
    function level(bytes12 vault) view returns (int128) {                 // Cost of `value` + `dues`
        return value(vault) - dues(vault);
    }

    // ---- Liquidations ----
    // Each liquidation engine can:
    // - Mark vaults as not a target for liquidation
    // - Donate assets to the Vat
    // - Cancel debt in liquidation vaults at no cost
    // - Retrieve collateral from liquidation vaults
    // - Give vaults to non-privileged users
    // Giving a user vault to a liquidation engine means it will be auctioned and liquidated.
    // The vault will be returned to the user once it's healthy.
}