// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "../constants/Constants.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/DataTypes.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import { CauldronMath } from "../Cauldron.sol";
import { UUPSUpgradeable } from "openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";


contract VRCauldron is UUPSUpgradeable, AccessControl, Constants {
    using CauldronMath for uint128;
    using Math for uint256;
    using Cast for uint128;
    using Cast for int128;
    using Cast for uint256;

    event AssetAdded(bytes6 indexed assetId, address indexed asset);
    event BaseAdded(bytes6 indexed baseId);
    event IlkAdded(bytes6 indexed baseId, bytes6 indexed ilkId);
    event SpotOracleAdded(
        bytes6 indexed baseId,
        bytes6 indexed ilkId,
        address indexed oracle,
        uint32 ratio
    );
    event RateOracleAdded(bytes6 indexed baseId, address indexed oracle);
    event DebtLimitsSet(
        bytes6 indexed baseId,
        bytes6 indexed ilkId,
        uint96 max,
        uint24 min,
        uint8 dec
    );

    event VaultBuilt(
        bytes12 indexed vaultId,
        address indexed owner,
        bytes6 indexed baseId,
        bytes6 ilkId
    );
    event VaultTweaked(
        bytes12 indexed vaultId,
        bytes6 indexed baseId,
        bytes6 indexed ilkId
    );
    event VaultDestroyed(bytes12 indexed vaultId);
    event VaultGiven(bytes12 indexed vaultId, address indexed receiver);

    event VaultPoured(
        bytes12 indexed vaultId,
        bytes6 indexed baseId,
        bytes6 indexed ilkId,
        int128 ink,
        int128 art
    );
    event VaultStirred(
        bytes12 indexed from,
        bytes12 indexed to,
        uint128 ink,
        uint128 art
    );

    // ==== Upgradability data ====
    bool public initialized;

    // ==== Configuration data ====
    mapping(bytes6 => address) public assets; // Underlyings and collaterals available in Cauldron. 12 bytes still free.
    mapping(bytes6 => bool) public bases; // Assets available in Cauldron for borrowing.
    mapping(bytes6 => mapping(bytes6 => bool)) public ilks; // [baseId][assetId] Assets that are approved as collateral for the base

    mapping(bytes6 => IOracle) public rateOracles; // Variable rate oracle for an underlying
    mapping(bytes6 => mapping(bytes6 => DataTypes.SpotOracle)) public spotOracles; // [assetId][assetId] Spot price oracles

    // ==== Protocol data ====
    mapping(bytes6 => mapping(bytes6 => DataTypes.Debt)) public debt; // [baseId][ilkId] Max and sum of debt per underlying and collateral.

    // ==== User data ====
    mapping(bytes12 => VRDataTypes.Vault) public vaults; // An user can own one or more Vaults, each one with a bytes12 identifier
    mapping(bytes12 => DataTypes.Balances) public balances; // Both debt and assets

    constructor() {
        // See https://medium.com/immunefi/wormhole-uninitialized-proxy-bugfix-review-90250c41a43a
        initialized = true; // Lock the implementation contract
    }

    // ==== Upgradability ====

    /// @dev Give the ROOT role and create a LOCK role with itself as the admin role and no members. 
    /// Calling setRoleAdmin(msg.sig, LOCK) means no one can grant that msg.sig role anymore.
    function initialize (address root_) public {
        require(!initialized, "Already initialized");
        initialized = true;             // On an uninitialized contract, no governance functions can be executed, because no one has permission to do so
        _grantRole(ROOT, root_);        // Grant ROOT
        _setRoleAdmin(LOCK, LOCK);      // Create the LOCK role by setting itself as its own admin, creating an independent role tree
    }

    /// @dev Allow to set a new implementation
    function _authorizeUpgrade(address newImplementation) internal override auth {}

    // ==== Administration ====

    /// @dev Add a new Asset.
    function addAsset(bytes6 assetId, address asset) external auth {
        require(assetId != bytes6(0), "Asset id is zero");
        require(assets[assetId] == address(0), "Id already used");
        assets[assetId] = asset;
        emit AssetAdded(assetId, address(asset));
    }

    /// @dev Set the maximum and minimum debt for an underlying and ilk pair. Can be reset.
    function setDebtLimits(
        bytes6 baseId,
        bytes6 ilkId,
        uint96 max,
        uint24 min,
        uint8 dec
    ) external auth {
        require(assets[baseId] != address(0), "Base not found");
        require(assets[ilkId] != address(0), "Ilk not found");
        DataTypes.Debt memory debt_ = debt[baseId][ilkId];
        debt_.max = max;
        debt_.min = min;
        debt_.dec = dec;
        debt[baseId][ilkId] = debt_;
        emit DebtLimitsSet(baseId, ilkId, max, min, dec);
    }

    /// @dev Set a rate oracle. Can be reset.
    function setRateOracle(bytes6 baseId, IOracle oracle) external auth {
        require(assets[baseId] != address(0), "Base not found");
        rateOracles[baseId] = oracle;
        emit RateOracleAdded(baseId, address(oracle));
    }

    /// @dev Set a spot oracle and its collateralization ratio. Can be reset.
    function setSpotOracle(
        bytes6 baseId,
        bytes6 ilkId,
        IOracle oracle,
        uint32 ratio
    ) external auth {
        require(assets[baseId] != address(0), "Base not found");
        require(assets[ilkId] != address(0), "Ilk not found");
        spotOracles[baseId][ilkId] = DataTypes.SpotOracle({
            oracle: oracle,
            ratio: ratio // With 6 decimals. 1000000 == 100%
        }); // Allows to replace an existing oracle.
        emit SpotOracleAdded(baseId, ilkId, address(oracle), ratio);
    }

    /// @dev Add a new base
    function addBase(bytes6 baseId) external auth {
        address base = assets[baseId];
        require(base != address(0), "Base not found");
        require(
            rateOracles[baseId] != IOracle(address(0)),
            "Rate oracle not found"
        );
        bases[baseId] = true;
        emit BaseAdded(baseId);
    }

    /// @dev Add a new Ilk (approve an asset as collateral for a base).
    function addIlks(bytes6 baseId, bytes6[] calldata ilkIds) external auth {
        require(bases[baseId], "Base not found");
        for (uint256 i; i < ilkIds.length; i++) {
            require(
                spotOracles[baseId][ilkIds[i]].oracle != IOracle(address(0)),
                "Spot oracle not found"
            );
            ilks[baseId][ilkIds[i]] = true;
            emit IlkAdded(baseId, ilkIds[i]);
        }
    }

    // ==== Vault management ====

    /// @dev Create a new vault, linked to a base and a collateral
    function build(
        address owner,
        bytes12 vaultId,
        bytes6 baseId,
        bytes6 ilkId
    ) external auth returns (VRDataTypes.Vault memory vault) {
        require(vaultId != bytes12(0), "Vault id is zero");
        require(baseId != bytes6(0), "Base id is zero");
        require(ilkId != bytes6(0), "Ilk id is zero");
        require(vaults[vaultId].baseId == bytes6(0), "Vault already exists"); // Base can't take bytes6(0) as their id
        require(ilks[baseId][ilkId] == true, "Ilk not added to base");
        vault = VRDataTypes.Vault({owner: owner, baseId: baseId, ilkId: ilkId});
        vaults[vaultId] = vault;

        emit VaultBuilt(vaultId, owner, baseId, ilkId);
    }

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId) external auth {
        require(vaults[vaultId].baseId != bytes6(0), "Vault doesn't exist"); // Bases can't take bytes6(0) as their id
        DataTypes.Balances memory balances_ = balances[vaultId];
        require(balances_.art == 0 && balances_.ink == 0, "Only empty vaults");
        delete vaults[vaultId];
        emit VaultDestroyed(vaultId);
    }

    /// @dev Change a vault base and/or collateral types.
    /// We can change the base if there is no debt, or assets if there are no assets
    function _tweak(
        bytes12 vaultId,
        bytes6 baseId,
        bytes6 ilkId
    ) internal returns (VRDataTypes.Vault memory vault) {
        require(baseId != bytes6(0), "Base id is zero");
        require(ilkId != bytes6(0), "Ilk id is zero");
        require(ilks[baseId][ilkId] == true, "Ilk not added to base");

        vault = vaults[vaultId];
        require(vault.baseId != bytes6(0), "Vault doesn't exist"); // Bases can't take bytes6(0) as their id

        DataTypes.Balances memory balances_ = balances[vaultId];
        if (baseId != vault.baseId) {
            require(balances_.art == 0, "Only with no debt");
            vault.baseId = baseId;
        }
        if (ilkId != vault.ilkId) {
            require(balances_.ink == 0, "Only with no collateral");
            vault.ilkId = ilkId;
        }

        vaults[vaultId] = vault;
        emit VaultTweaked(vaultId, vault.baseId, vault.ilkId);
    }

    /// @dev Change a vault base and/or collateral types.
    /// We can change the base if there is no debt, or assets if there are no assets
    function tweak(
        bytes12 vaultId,
        bytes6 baseId,
        bytes6 ilkId
    ) external auth returns (VRDataTypes.Vault memory vault) {
        vault = _tweak(vaultId, baseId, ilkId);
    }

    /// @dev Transfer a vault to another user.
    function _give(bytes12 vaultId, address receiver)
        internal
        returns (VRDataTypes.Vault memory vault)
    {
        require(vaultId != bytes12(0), "Vault id is zero");
        require(vaults[vaultId].baseId != bytes6(0), "Vault doesn't exist"); // Base can't take bytes6(0) as their id
        vault = vaults[vaultId];
        vault.owner = receiver;
        vaults[vaultId] = vault;
        emit VaultGiven(vaultId, receiver);
    }

    /// @dev Transfer a vault to another user.
    function give(bytes12 vaultId, address receiver)
        external
        auth
        returns (VRDataTypes.Vault memory vault)
    {
        vault = _give(vaultId, receiver);
    }

    // ==== Asset and debt management ====

    function vaultData(bytes12 vaultId)
        internal
        view
        returns (
            VRDataTypes.Vault memory vault_,
            DataTypes.Balances memory balances_
        )
    {
        vault_ = vaults[vaultId];
        require(vault_.baseId != bytes6(0), "Vault not found");
        balances_ = balances[vaultId];
    }

    /// @dev Convert a base amount to debt terms.
    /// @notice Think about rounding up if using, since we are dividing.
    function debtFromBase(bytes6 baseId, uint128 base)
        external
        returns (uint128 art)
    {
        art = _debtFromBase(baseId, base);
    }

    /// @dev Convert a base amount to debt terms.
    /// @notice Think about rounding up if using, since we are dividing.
    function _debtFromBase(bytes6 baseId, uint128 base)
        internal
        returns (uint128 art)
    {
        (uint256 rate, ) = rateOracles[baseId].get(baseId, RATE, 0); // The value returned is an accumulator, it doesn't need an input amount
        art = uint256(base).wdivup(rate).u128();
    }

    /// @dev Convert a debt amount for a to base terms
    function debtToBase(bytes6 baseId, uint128 art)
        external
        returns (uint128 base)
    {
        base = _debtToBase(baseId, art);
    }

    /// @dev Convert a debt amount for a to base terms
    function _debtToBase(bytes6 baseId, uint128 art)
        internal
        returns (uint128 base)
    {
        (uint256 rate, ) = rateOracles[baseId].get(baseId, RATE, 0); // The value returned is an accumulator, it doesn't need an input amount
        base = uint256(art).wmul(rate).u128();
    }

    /// @dev Move collateral and debt between vaults.
    function stir(
        bytes12 from,
        bytes12 to,
        uint128 ink,
        uint128 art
    )
        external
        auth
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        require(from != to, "Identical vaults");
        (
            VRDataTypes.Vault memory vaultFrom,
            DataTypes.Balances memory balancesFrom
        ) = vaultData(from);
        (
            VRDataTypes.Vault memory vaultTo,
            DataTypes.Balances memory balancesTo
        ) = vaultData(to);

        if (ink > 0) {
            require(vaultFrom.ilkId == vaultTo.ilkId, "Different collateral");
            balancesFrom.ink -= ink;
            balancesTo.ink += ink;
        }
        if (art > 0) {
            require(vaultFrom.baseId == vaultTo.baseId, "Different base");
            balancesFrom.art -= art;
            balancesTo.art += art;
        }

        balances[from] = balancesFrom;
        balances[to] = balancesTo;

        if (ink > 0)
            require(
                _level(vaultFrom, balancesFrom) >= 0,
                "Undercollateralized at origin"
            );
        if (art > 0)
            require(
                _level(vaultTo, balancesTo) >= 0,
                "Undercollateralized at destination"
            );

        emit VaultStirred(from, to, ink, art);
        return (balancesFrom, balancesTo);
    }

    /// @dev Add collateral and rate from vault, pull assets from and push rateed asset to user
    /// Or, repay to vault and remove collateral, pull rateed asset from and push assets to user
    function _pour(
        bytes12 vaultId,
        VRDataTypes.Vault memory vault_,
        DataTypes.Balances memory balances_,
        int128 ink,
        int128 art
    ) internal returns (DataTypes.Balances memory) {
        // For now, the collateralization checks are done outside to allow for underwater operation. That might change.
        if (ink != 0) {
            balances_.ink = balances_.ink.add(ink);
        }

        // Modify vault and global debt records. If debt increases, check global limit.
        if (art != 0) {
            DataTypes.Debt memory debt_ = debt[vault_.baseId][vault_.ilkId];
            balances_.art = balances_.art.add(art);
            debt_.sum = debt_.sum.add(art);
            uint128 dust = debt_.min * uint128(10)**debt_.dec;
            uint128 line = debt_.max * uint128(10)**debt_.dec;
            require(
                balances_.art == 0 || balances_.art >= dust,
                "Min debt not reached"
            );
            if (art > 0) require(debt_.sum <= line, "Max debt exceeded");
            debt[vault_.baseId][vault_.ilkId] = debt_;
        }
        balances[vaultId] = balances_;

        emit VaultPoured(vaultId, vault_.baseId, vault_.ilkId, ink, art);
        return balances_;
    }

    /// @dev Manipulate a vault, ensuring it is collateralized afterwards.
    /// To be used by debt management contracts.
    function pour(
        bytes12 vaultId,
        int128 ink,
        int128 base
    ) external virtual auth returns (DataTypes.Balances memory) {
        (
            VRDataTypes.Vault memory vault_,
            DataTypes.Balances memory balances_
        ) = vaultData(vaultId);

        // Normalize the base amount to debt terms
        int128 art = base;

        if (base != 0)
            art = base > 0
                ? _debtFromBase(vault_.baseId, base.u128()).i128()
                : -_debtFromBase(vault_.baseId, (-base).u128()).i128();

        balances_ = _pour(vaultId, vault_, balances_, ink, art);

        if (balances_.art > 0 && (ink < 0 || art > 0))
            // If there is debt and we are less safe
            require(_level(vault_, balances_) >= 0, "Undercollateralized");
        return balances_;
    }

    /// @dev Reduce debt and collateral from a vault, ignoring collateralization checks.
    /// To be used by liquidation engines.
    function slurp(
        bytes12 vaultId,
        uint128 ink,
        uint128 base
    ) external auth returns (DataTypes.Balances memory) {
        (
            VRDataTypes.Vault memory vault_,
            DataTypes.Balances memory balances_
        ) = vaultData(vaultId);

        // Normalize the base amount to debt terms
        int128 art = _debtFromBase(vault_.baseId, base).i128();

        balances_ = _pour(vaultId, vault_, balances_, -(ink.i128()), -art);

        return balances_;
    }

    // ==== Accounting ====

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    function level(bytes12 vaultId) external returns (int256) {
        (
            VRDataTypes.Vault memory vault_,
            DataTypes.Balances memory balances_
        ) = vaultData(vaultId);

        return _level(vault_, balances_);
    }

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    function _level(
        VRDataTypes.Vault memory vault_,
        DataTypes.Balances memory balances_
    ) internal returns (int256) {
        DataTypes.SpotOracle memory spotOracle_ = spotOracles[vault_.baseId][
            vault_.ilkId
        ];
        uint256 ratio = uint256(spotOracle_.ratio) * 1e12; // Normalized to 18 decimals
        (uint256 inkValue, ) = spotOracle_.oracle.get(
            vault_.ilkId,
            vault_.baseId,
            balances_.ink
        ); // ink * spot
        uint256 baseValue = _debtToBase(vault_.baseId, balances_.art); // art * rate
        return inkValue.i256() - baseValue.wmul(ratio).i256();
    }
}