// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./interfaces/IFYToken.sol";
import "./interfaces/IJoin.sol";
import "./interfaces/ICauldron.sol";
import "./interfaces/IOracle.sol";
import "./libraries/DataTypes.sol";


library RMath { // Fixed point arithmetic in Ray units
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            uint256 _z = uint256(x) * uint256(y) / 1e27;
            require (_z <= type(uint128).max, "RMUL Overflow");
            z = uint128(_z);
        }
    }
}

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
/// TODO: Rename to highlight that this is a core contract that manages debt. The handling of Joins might be a base class to this and other contracts.
contract Ladle {
    using RMath for uint128;

    ICauldron public cauldron;

    // TODO: Consider making assets and assets a single variable
    mapping (bytes6 => IJoin)                public joins;           // Join contracts available to manage collateral. 12 bytes still free.

    event JoinAdded(bytes6 indexed assetId, address indexed join);

    constructor (ICauldron cauldron_) {
        cauldron = cauldron_;
    }

    /// @dev Add a new Join for an Asset. There can be only onw Join per Asset. Until a Join is added, no tokens of that Asset can be posted or withdrawn.
    function addJoin(bytes6 assetId, IJoin join)
        external
        /*auth*/
    {
        require (cauldron.assets(assetId) != IERC20(address(0)), "Asset not found");    // 1 CALL + 1 SLOAD
        require (joins[assetId] == IJoin(address(0)), "One Join per Asset");            // 1 SLOAD
        joins[assetId] = join;                                                          // 1 SSTORE
        emit JoinAdded(assetId, address(join));
    }

    // Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    // Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    // Doesn't check inputs, or collateralization level. Do that in public functions.
    // TODO: Extend to allow other accounts in `join`
    function stir(bytes12 vaultId, int128 ink, int128 art)
        external
        returns (DataTypes.Balances memory balances_)
    {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");

        if (ink != 0) joins[vault_.ilkId].join(vault_.owner, ink);                      // Cost of `join`. `join` with a negative value means `exit`. | TODO: Consider checking the join exists

        balances_ = cauldron._stir(vaultId, ink, art);                                  // Cost of `cauldron.stir` call.

        if (art != 0) {
            DataTypes.Series memory series_ = cauldron.series(vault_.seriesId);         // 1 CALL + 1 SLOAD
            // TODO: Consider checking the series exists
            if (art > 0) {
                require(uint32(block.timestamp) <= series_.maturity, "Mature");
                IFYToken(series_.fyToken).mint(msg.sender, uint128(art));               // 1 CALL(40) + fyToken.mint. Consider whether it's possible to achieve this without an external call, so that `Cauldron` doesn't depend on the `FYDai` interface.
            } else {
                IFYToken(series_.fyToken).burn(msg.sender, uint128(-art));              // 1 CALL(40) + fyToken.burn. Consider whether it's possible to achieve this without an external call, so that `Cauldron` doesn't depend on the `FYDai` interface.
            }
        }

        return balances_;
    }

    /// @dev Repay vault debt using underlying token. It can add or remove collateral at the same time.
    /// The debt to repay is denominated in fyToken, even if the tokens pulled from the user are underlying.
    /// The debt to repay must be entered as a negative number, as with `stir`.
    /// Debt cannot be acquired with this function.
    function close(bytes12 vaultId, int128 ink, int128 art)
        external
        returns (DataTypes.Balances memory balances_)
    {
        require (art <= 0, "Only repay debt");                                          // When repaying debt in `frob`, art is a negaive value. Here is the same for consistency.
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");

        DataTypes.Series memory series_ = cauldron.series(vault_.seriesId);             // 1 CALL + 1 SLOAD
        bytes6 baseId = series_.baseId;

        // Converting from fyToken debt to underlying amount allows us to repay an exact amount of debt,
        // avoiding rounding errors and the need to pull only as much underlying as we can use.
        uint128 amt;
        if (uint32(block.timestamp) >= series_.maturity) {
            IOracle rateOracle = cauldron.rateOracles(baseId);                          // 1 CALL + 1 SLOAD
            amt = uint128(-art).rmul(rateOracle.accrual(series_.maturity));             // Cost of `accrual`
        } else {
            amt = uint128(-art);
        }

        if (ink != 0) joins[vault_.ilkId].join(vault_.owner, ink);                      // Cost of `join`. `join` with a negative value means `exit`. | TODO: Consider checking the join exists
        joins[baseId].join(msg.sender, int128(amt));                                    // Cost of `join`
        
        return cauldron._stir(vaultId, ink, art);                                       // Cost of `_stir`
    }

    /// @dev Allow authorized contracts to move assets through the ladle
    function _join(bytes12 vaultId, address user, int128 ink, int128 art)
        external
        // auth
    {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        DataTypes.Series memory series_ = cauldron.series(vault_.seriesId);             // 1 CALL + 1 SLOAD

        if (ink != 0) joins[vault_.ilkId].join(user, ink);                              // 1 SLOAD + Cost of `join`
        if (art != 0) joins[series_.baseId].join(user, art);                            // 1 SLOAD + Cost of `join`
    }
}