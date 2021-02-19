// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./IFYToken.sol";
import "./IJoin.sol";
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "../libraries/DataTypes.sol";


interface IVat {
    /// @dev Add a collateral to Vat
    // function addAsset(bytes6 id, address asset) external;

    /// @dev Add an underlying to Vat
    // function addAsset(address asset) external;

    /// @dev Add a series to Vat
    // function addSeries(bytes32 series, IERC20 asset, IFYToken fyToken) external;

    /// @dev Add a spot oracle to Vat
    // function addSpotOracle(IERC20 asset, IERC20 asset, IOracle oracle) external;

    /// @dev Add a chi oracle to Vat
    // function addChiOracle(IERC20 asset, IOracle oracle) external;

    /// @dev Add a rate oracle to Vat
    // function addRateOracle(IERC20 asset, IOracle oracle) external;

    /// @dev Spot price oracle for an underlying and collateral
    // function chiOracles(bytes6 asset, bytes6 asset) external returns (address);

    /// @dev Chi (savings rate) accruals oracle for an underlying
    // function chiOracles(bytes6 asset) external returns (address);

    /// @dev Rate (borrowing rate) accruals oracle for an underlying
    // function rateOracles(bytes6 asset) external returns (address);

    /// @dev An user can own one or more Vaults, with each vault being able to borrow from a single series.
    function vaults(bytes12 vault) external view returns (DataTypes.Vault memory);

    /// @dev Series available in Vat.
    function series(bytes6 seriesId) external returns (DataTypes.Series memory);

    /// @dev Collaterals available in Vat.
    function assets(bytes6 assetsDd) external returns (IERC20);

    /// @dev Underlyings available in Vat.
    // function assets(bytes6 id) external returns (IERC20);

    /// @dev Each vault records debt and collateral balances.
    // function vaultBalances(bytes12 vault) external view returns (Balances);

    /// @dev Time at which a vault entered liquidation.
    // function timestamps(bytes12 vault) external view returns (uint32);

    /// @dev Create a new vault, linked to a series (and therefore underlying) and up to 5 collateral types
    // function build(bytes12 series, bytes32 assets) external returns (bytes12 id);

    /// @dev Destroy an empty vault. Used to recover gas costs.
    // function destroy(bytes12 vault) external;


    // ---- Restricted processes ----
    // Usable only by a authorized modules that won't cheat on Vat.

    /// @dev Change series and debt of a vault.
    /// The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    // function _roll(bytes12 vault, bytes6 series, uint128 art) external;

    /// @dev Give a non-timestamped vault to the caller, and timestamp it.
    /// To be used for liquidation engines.
    // function _grab(bytes12 vault) external;

    /// @dev Manipulate a vault debt and collateral.
    function _frob(bytes12 vault, int128 ink, int128 art) external returns (DataTypes.Balances memory);

    // ---- Public processes ----

    /// @dev Give a vault to another user.
    // function give(bytes12 vault, address user) external;

    /// @dev Move collateral between vaults.
    // function flux(bytes12 from, bytes12 to, bytes1 assets, uint128[] memory inks) external returns (Balances, Balances);

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    /// Checks the vault is valid, and collateralization levels at the end.
    // function frob(bytes12 vault, bytes1 assets,  int128[] memory inks, int128 art) external returns (Balances);

    /// @dev Repay vault debt using underlying token, pulled from user. Collateral is returned to caller
    // function close(bytes12 vault, bytes1 assets, int128[] memory inks, uint128 repay) external returns (Balances);

    // ==== Accounting ====

    /// @dev Return the vault debt in underlying terms
    // function dues(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the capacity of the vault to borrow underlying assetd on the assets held
    // function value(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    // function level(bytes12 vault) external view returns (int128);
}