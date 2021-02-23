// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./interfaces/IFYToken.sol";
import "./interfaces/IJoin.sol";
import "./interfaces/IVat.sol";
// import "./interfaces/IOracle.sol";
import "./libraries/DataTypes.sol";

/// @dev CDPProxy orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
/// TODO: Rename to highlight that this is a core contract that manages debt. The handling of Joins might be a base class to this and other contracts.
contract CDPProxy {

    IVat public vat;

    // TODO: Consider making assets and assets a single variable
    mapping (bytes6 => IJoin)                public joins;           // Join contracts available to manage collateral. 12 bytes still free.

    event JoinAdded(bytes6 indexed assetId, address indexed join);

    constructor (IVat vat_) {
        vat = vat_;
    }

    /// @dev Add a new Join for an Asset. There can be only onw Join per Asset. Until a Join is added, no tokens of that Asset can be posted or withdrawn.
    function addJoin(bytes6 assetId, IJoin join)
        external
        /*auth*/
    {
        require (vat.assets(assetId) != IERC20(address(0)), "Asset not found"); // 1 CALL + 1 SLOAD
        require (joins[assetId] == IJoin(address(0)), "One Join per Asset");    // 1 SLOAD
        joins[assetId] = join;                                                  // 1 SSTORE
        emit JoinAdded(assetId, address(join));
    }

    // Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    // Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    // TODO: Extend to allow other accounts in `join`
    function frob(bytes12 vaultId, int128 ink, int128 art)
        external
        returns (DataTypes.Balances memory _balances)
    {
        DataTypes.Vault memory _vault = vat.vaults(vaultId);                // 1 CALL + 1 SLOAD
        require (_vault.owner == msg.sender, "Only vault owner");

        if (ink != 0) {
            // TODO: Consider checking the join exists
            joins[_vault.ilkId].join(_vault.owner, ink);                    // Cost of `join` call. `join` with a negative value means `exit`.
        }

        _balances = vat._frob(vaultId, ink, art);                           // Cost of `vat.frob` call.

        if (art != 0) {
            DataTypes.Series memory _series = vat.series(_vault.seriesId);  // 1 CALL + 1 SLOAD
            // TODO: Consider checking the series exists
            if (art > 0) {
                require(block.timestamp <= _series.maturity, "Mature");
                IFYToken(_series.fyToken).mint(msg.sender, uint128(art));   // 1 CALL(40) + fyToken.mint. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `FYDai` interface.
            } else {
                IFYToken(_series.fyToken).burn(msg.sender, uint128(-art));  // 1 CALL(40) + fyToken.burn. Consider whether it's possible to achieve this without an external call, so that `Vat` doesn't depend on the `FYDai` interface.
            }
        }

        return _balances;
    }

    /// @dev Repay vault debt using underlying token. It can add or remove collateral at the same time.
    /* function close(bytes12 vaultId, int128 ink, uint128 repay)
        external
        returns (DataTypes.Balances memory _balances)
    {
        DataTypes.Vault memory _vault = vat.vaults(vaultId);                        // 1 CALL + 1 SLOAD
        require (_vault.owner == msg.sender, "Only vault owner");

        DataTypes.Series memory _series = vat.series(_vault.seriesId);              // 1 CALL + 1 SLOAD
        bytes6 assetId = _series[vaultId].assetId;                                  // 1 SLOAD
        joins[assetId].join(int128(repay));                                         // Cost of `join`
        uint128 art = repay * RAY / rateOracles[asset].accrual(_series.maturity);   // 1 SLOAD + `spot`
        return __frob(vaultId, ink, -int128(art));                                  // Cost of `__frob`
    } */
}