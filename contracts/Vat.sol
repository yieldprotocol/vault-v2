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
    function addCollateral(bytes6 id, address collateral)
    function addUnderlying(address underlying)                       
    function addSeries(bytes32 series, IERC20 underlying, IFYToken fyToken)
    function addOracle(IERC20 underlying, IERC20 collateral, IOracle oracle)

    mapping (bytes6 => address)                     chiOracles         // Chi accruals oracle for the underlying
    mapping (bytes6 => address)                     rateOracles        // Rate accruals oracle for the underlying
    mapping (bytes6 => mapping(bytes6 => address))  spotOracles        // [underlying][collateral] Spot oracles
    mapping (address => mapping(bytes6 => uint128)) safe               // safe[user][collateral] The `safe` of each user contains assets (including fyDai) that are not assigned to any vault, and therefore unencumbered.

    struct Series {
        address fyToken;
        uint32  maturity;
        // bytes8 free;
    }

    mapping (bytes12 => Series)                     series             // Series available in Vat. We can possibly use a bytes6 (3e14 possible series).
    mapping (bytes6 => bool)                        collaterals        // Collaterals available in Vat. A whole word to pack in.

    // ---- Vault ordering ----
    struct Vault {
        address owner;
        bytes12 next;
        bytes12 series;                                                // address to pack next to it. Each vault is related to only one series, which also determines the underlying.
    }

    mapping (address => bytes12)                    first              // Pointer to the first vault in the user's list. We have 20 bytes here that we can still use.
    mapping (bytes12 => Vault)                      vaults             // With a vault identifier we can get both the owner and the next in the list. When giving a vault both are changed with 1 SSTORE.

    // ---- Vault composition ----
    struct Collaterals {
        bytes6[5] ids;
        bytes2 length;
    }

    struct Balances {
        uint128 debt;
        uint128[5] assets;
    }

    // An user can own one or more Vaults, each one with a bytes12 identifier so that we can pack a singly linked list and a reverse search in a bytes32
    mapping (bytes12 => Collaterals)                vaultCollaterals   // Collaterals are identified by just 6 bytes, then in 32 bytes (one SSTORE) we can have an array of 5 collateral types to allow multi-collateral vaults. 
    mapping (bytes12 => Balances)                   vaultBalances      // Both debt and assets. The debt and the amount held for the first collateral share a word.

    // ---- Vault management ----
    // Create a new vault, linked to a series (and therefore underlying) and up to 6 collateral types
    // 2 SSTORE for series and up to 6 collateral types, plus 2 SSTORE for vault ownership.
    function build(bytes12 series, bytes32 collaterals)
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

        require (validCollaterals(collaterals), "Invalid collaterals");// C SLOAD.
        Collaterals memory _collaterals = ({
            ids: collaterals.slice(0, 30);
            length: collaterals.slice(30, 32);
        });
        collaterals[id] = _collaterals;                                // 1 SSTORE
    }

    // Change a vault series and/or collateral types. 2 SSTORE.
    // We can change the series if there is no debt, or collaterals types if there is no collateral
    function tweak(bytes12 vault, bytes12 series, bytes32 collaterals)

    // Move collateral between vaults.
    function __flux(bytes12 from, bytes12 to, bytes32 collaterals, uint128[] memory inks)
        internal
    {
        Balances memory _balancesFrom = balances[from];                               // 1 SLOAD
        Balances memory _balancesTo = balances[to];                                   // 1 SLOAD
        for each ilk in ilks {
            _balancesFrom.assets[ilk] -= inks[ilk];
            _balancesTo.assets[ilk] += inks[ilk];
        }
        balances[from] = _balancesFrom;                                               // 1 SSTORE
        balances[to] = _balancesTo;                                                   // 1 SSTORE
    }

    // Move collateral between a vault and its owner's safe
    function __save(bytes12 vault, bytes6[] memory ilks, int128[] memory inks)
        internal
    {
        address _owner = vaults[vault].owner;                                         // 1 SLOAD
        Balances memory _balances = balances[vault];                                  // 1 SLOAD
        for each ilk in ilks {
            _balances.assets[ilk] -= inks[ilk];
            safe[_owner][ilk] += inks[ilk];                                           // 1 SSTORE
        }
        balances[id] = _balances;                                                     // 1 SSTORE
    }

    // Move collateral between an external account and a safe
    function __slip(address owner, bytes6[] memory ilks, int128[] memory inks)
        internal
    {
        address _owner = vaults[vault].owner;                                         // 1 SLOAD
        for each ilk in ilks {
            joins[ilk].join(inks[ilk]);                                               // Cost of `join`. `join` with a negative value means `exit`
            safe[_owner][ilk] += inks[ilk];                                           // 1 SSTORE
        }
    }

    // Move debt from one vault to another (like when rolling a series). 2 SSTORE.
    // Note, it won't be possible if the Vat doesn't know about pools
    function move(bytes12 from, bytes12 to, uint128 art)

    // Move collateral and debt. Combine costs of `flux` and `move`, minus 1 SSTORE.
    // Note, it won't be possible if the Vat doesn't know about pools
    function roll(bytes12 from, bytes12 to, bytes32 collaterals, uint128[] memory inks, uint128 art)

    // Transfer vault to another user. 2 or 3 SSTORE.
    function give(bytes12 vault, address user)

    // Add collateral and borrow from vault, pull collaterals from and push borrowed asset to user
    // Repay to vault and remove collateral, pull borrowed asset from and push collaterals to user
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
        balances[id] = _balances;                                                     // 1 SSTORE. Refactor for Checks-Effects-Interactions

        return _balances;
    }
    
    // Add collateral and borrow from vault, pull collaterals from and push borrowed asset to user
    // Repay to vault and remove collateral, pull borrowed asset from and push collaterals to user
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

    // Repay vault debt using underlying token, pulled from user. Collaterals are pushed to user. 
    function close(bytes12 vault, bytes32 collaterals, uint128[] memory inks, uint128 art) // Same cost as `frob`

    // ---- Accounting ----

    // Return the vault debt in underlying terms
    function dues(bytes12 vault) view returns (uint128 uart) {
        uint32 maturity = series[vault].maturity;                         // 1 SLOAD
        IFYToken fyToken = _series.fyToken;
        if (block.timestamp >= maturity) {
            IOracle oracle = rateOracles[underlying];                     // 1 SLOAD
            uart = balances[vault].debt * oracle.accrual(maturity);       // 1 SLOAD + 1 Oracle Call
        } else {
            uart = balances[vault].debt;                                  // 1 SLOAD
        }
    }

    // Return the capacity of the vault to borrow underlying based on the collaterals held
    function value(bytes12 vault) view returns (uint128 uart) {
        Collaterals memory _collaterals = collaterals[vault];             // 1 SLOAD
        Balances memory _balances = balances[vault];                      // 1 SLOAD
        for each collateral {                                             // * C
            IOracle oracle = spotOracles[underlying][collateral];         // 1 SLOAD
            uart += _balances[collateral] * oracle.spot();                // 1 Oracle Call | Divided by collateralization ratio
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