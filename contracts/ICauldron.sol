// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./IFYToken.sol";
import "./IOracle.sol";
import "./DataTypes.sol";


interface ICauldron {
    /// @dev Add a collateral to Cauldron
    // function addAsset(bytes6 id, address asset) external;

    /// @dev Add an underlying to Cauldron
    // function addAsset(address asset) external;

    /// @dev Add a series to Cauldron
    // function addSeries(bytes32 series, IERC20 asset, IFYToken fyToken) external;

    /// @dev Add a spot oracle to Cauldron
    // function setSpotOracle(IERC20 asset, IERC20 asset, IOracle oracle) external;

    /// @dev Add a chi oracle to Cauldron
    // function addChiOracle(IERC20 asset, IOracle oracle) external;

    /// @dev Add a rate oracle to Cauldron
    // function addRateOracle(IERC20 asset, IOracle oracle) external;

    /// @dev Spot price oracle for an underlying and collateral
    // function chiOracles(bytes6 asset, bytes6 asset) external returns (address);

    /// @dev Chi (savings rate) accruals oracle for an underlying
    // function chiOracles(bytes6 asset) external returns (address);

    /// @dev Rate (borrowing rate) accruals oracle for an underlying
    function rateOracles(bytes6 baseId) external view returns (IOracle);

    /// @dev An user can own one or more Vaults, with each vault being able to borrow from a single series.
    function vaults(bytes12 vault) external view returns (DataTypes.Vault memory);

    /// @dev Series available in Cauldron.
    function series(bytes6 seriesId) external view returns (DataTypes.Series memory);

    /// @dev Assets available in Cauldron.
    function assets(bytes6 assetsId) external view returns (address);

    /// @dev Each vault records debt and collateral balances_.
    function balances(bytes12 vault) external view returns (DataTypes.Balances memory);

    /// @dev Time at which a vault entered liquidation.
    function timestamps(bytes12 vault) external view returns (uint32);

    /// @dev Create a new vault, linked to a series (and therefore underlying) and up to 5 collateral types
    function build(address owner, bytes12 vaultId, bytes6 seriesId, bytes6 ilkId) external returns (DataTypes.Vault memory);

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vault) external;

    /// @dev Change a vault series and/or collateral types.
    function tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId) external returns (DataTypes.Vault memory);

    /// @dev Give a vault to another user.
    function give(bytes12 vaultId, address user) external returns (DataTypes.Vault memory);

    /// @dev Move collateral and debt between vaults.
    function stir(bytes12 from, bytes12 to, uint128 ink, uint128 art) external returns (DataTypes.Balances memory, DataTypes.Balances memory);

    /// @dev Manipulate a vault debt and collateral.
    function pour(bytes12 vaultId, int128 ink, int128 art) external returns (DataTypes.Balances memory);

    /// @dev Change series and debt of a vault.
    /// The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    function roll(bytes12 vaultId, bytes6 seriesId, int128 art) external returns (uint128);

    /// @dev Give a non-timestamped vault to the caller, and timestamp it.
    /// To be used for liquidation engines.
    function grab(bytes12 vault) external;

    /// @dev Reduce debt and collateral from a vault, ignoring collateralization checks.
    function slurp(bytes12 vaultId, uint128 ink, uint128 art) external returns (DataTypes.Balances memory);

    // ==== Accounting ====

    /// @dev Return the vault debt in underlying terms
    // function dues(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the capacity of the vault to borrow underlying assetd on the assets held
    // function value(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    // function level(bytes12 vault) external view returns (int128);
}