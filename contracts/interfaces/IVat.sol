// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./IJoin.sol";
import "@yield-protocol/utils/contracts/token/IERC20.sol";


interface IVat {
    /// @dev Add a collateral to Vat
    function addIlk(bytes6 id, address ilk) external;

    /// @dev Add an underlying to Vat
    function addBase(address base) external;

    /// @dev Add a series to Vat
    function addSeries(bytes32 series, IERC20 base, IFYToken fyToken) external;

    /// @dev Add a spot oracle to Vat
    function addSpotOracle(IERC20 base, IERC20 ilk, IOracle oracle) external;

    /// @dev Add a chi oracle to Vat
    function addChiOracle(IERC20 base, IOracle oracle) external;

    /// @dev Add a rate oracle to Vat
    function addRateOracle(IERC20 base, IOracle oracle) external;

    /// @dev Spot price oracle for an underlying and collateral
    function chiOracles(bytes6 base, bytes6 ilk) external returns (address);

    /// @dev Chi (savings rate) accruals oracle for an underlying
    function chiOracles(bytes6 base) external returns (address);

    /// @dev Rate (borrowing rate) accruals oracle for an underlying
    function rateOracles(bytes6 base) external returns (address);

    struct Series {
        address fyToken;                                               // Redeemable token for the series.
        uint32  maturity;                                              // Unix time at which redemption becomes possible.
        bytes6  base;                                                  // Token received on redemption.
        // bytes2 free
    }

    /// @dev Series available in Vat.
    function series(bytes6 id) external returns (Series);

    /// @dev Underlyings available in Vat.
    function bases(bytes6 id) external returns (IERC20);

    /// @dev Collaterals available in Vat.
    function ilks(bytes6 id) external returns (IERC20);

    /// @dev Joins (token bridges) available in Vat.
    function joins(bytes6 id) external returns (IJoin);

    struct Vault {
        address owner;
        bytes6 series;                                                 // Each vault is related to only one series, which also determines the underlying.
        // 6 bytes free
    }

    struct Ilks {
        bytes6[5] ids;
        bytes2 length;
    }

    struct Balances {
        uint128 debt;
        uint128[5] assets;
    }

    /// @dev An user can own one or more Vaults, with each vault being able to borrow from a single series.
    function vaults(bytes12 vault) external view returns (Vault);

    /// @dev Each vault can have up to 5 collateral types associated.
    function vaultIlks(bytes12 vault) external view returns (Ilks);

    /// @dev Each vault records debt and collateral balances.
    function vaultBalances(bytes12 vault) external view returns (Balances);

    /// @dev Time at which a vault entered liquidation.
    function timestamps(bytes12 vault) external view returns (uint32);

    /// @dev Create a new vault, linked to a series (and therefore underlying) and up to 5 collateral types
    function build(bytes12 series, bytes32 ilks) external returns (bytes12 id);

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vault) external;


    // ---- Restricted processes ----
    // Usable only by a authorized modules that won't cheat on Vat.

    /// @dev Change series and debt of a vault.
    /// The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    function _roll(bytes12 vault, bytes6 series, uint128 art) external;

    /// @dev Give a non-timestamped vault to the caller, and timestamp it.
    /// To be used for liquidation engines.
    function _grab(bytes12 vault) external;

    /// @dev Manipulate a vault without collateralization checks.
    /// To be used for liquidation engines.
    /// TODO: __frob underlying from and collateral to users
    function _frob(bytes12 vault, bytes1 ilks,  int128[] memory inks, int128 art) external returns (Balances);

    // ---- Public processes ----

    /// @dev Give a vault to another user.
    function give(bytes12 vault, address user) external;

    /// @dev Move collateral between vaults.
    function flux(bytes12 from, bytes12 to, bytes1 ilks, uint128[] memory inks) external returns (Balances, Balances);

    /// @dev Add collateral and borrow from vault, pull ilks from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push ilks to user
    /// Checks the vault is valid, and collateralization levels at the end.
    function frob(bytes12 vault, bytes1 ilks,  int128[] memory inks, int128 art) external returns (Balances);

    /// @dev Repay vault debt using underlying token, pulled from user. Collateral is returned to caller
    function close(bytes12 vault, bytes1 ilks, int128[] memory inks, uint128 repay) external returns (Balances);

    // ==== Accounting ====

    /// @dev Return the vault debt in underlying terms
    function dues(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the capacity of the vault to borrow underlying based on the ilks held
    function value(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    function level(bytes12 vault) external view returns (int128);
}