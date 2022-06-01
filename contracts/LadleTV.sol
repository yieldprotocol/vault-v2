// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol";
import "./LadleStorageV2.sol";

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract LadleTV is LadleStorageV2 {
    using WMul for uint256;
    using CastU256U128 for uint256;
    using CastU256I128 for uint256;
    using CastU128I128 for uint128;
    using TransferHelper for IERC20;
    using TransferHelper for address payable;

    constructor (ICauldron cauldron, IWETH9 weth) LadleStorageV2(cauldron, weth) { }

    // ---- Data sourcing ----
    /// @dev Obtains a vault by vaultId from the Cauldron, and verifies that msg.sender is the owner
    /// If bytes(0) is passed as the vaultId it tries to load a vault from the cache
    function getVault(bytes12 vaultId_)
        internal view
        returns (bytes12 vaultId, DataTypes.Vault memory vault)
    {
        if (vaultId_ == bytes12(0)) { // We use the cache
            require (cachedVaultId != bytes12(0), "Vault not cached");
            vaultId = cachedVaultId;
        } else {
            vaultId = vaultId_;
        }
        vault = cauldron.vaults(vaultId);
        require (vault.owner == msg.sender, "Only vault owner");
    } 
    /// @dev Obtains a series by seriesId from the Cauldron, and verifies that it exists
    function getSeries(bytes6 seriesId)
        internal view returns(DataTypes.Series memory series)
    {
        series = cauldron.series(seriesId);
        require (series.fyToken != IFYToken(address(0)), "Series not found");
    }

    /// @dev Obtains a join by assetId, and verifies that it exists
    function getJoin(bytes6 assetId)
        internal view returns(IJoin join)
    {
        join = joins[assetId];
        require (join != IJoin(address(0)), "Join not found");
    }

    /// @dev Obtains a pool by seriesId, and verifies that it exists
    function getPool(bytes6 seriesId)
        internal view returns(IPool pool)
    {
        pool = pools[seriesId];
        require (pool != IPool(address(0)), "Pool not found");
    }


    /// @dev Obtains a converter by wrapped asset address, and verifies that it exists
    function getConverter(address wrappedAsset)
        internal view returns(IConverter converter)
    {
        converter = converters[wrappedAsset];
        require (converter != IConverter(address(0)), "Converter not found");
    }

    // ---- Administration ----

    /// @dev Add or remove an integration.
    function _addIntegration(address integration, bool set)
        internal
    {
        integrations[integration] = set;
        emit IntegrationAdded(integration, set);
    }

    /// @dev Add or remove a token that the Ladle can call `transfer` or `permit` on.
    function _addToken(address token, bool set)
        internal
    {
        tokens[token] = set;
        emit TokenAdded(token, set);
    }


    /// @dev Add a new Converter for a Yield Bearing Vault, or replace an existing one for a new one.
    function addConverter(address ybvToken, IConverter converter)
        public
        auth
    {
        _addConverter(ybvToken, converter);
    }

    /// @dev Add a new Converter for a Yield Bearing Vault, or replace an existing one for a new one.
    function _addConverter(address ybvToken, IConverter converter)
        internal
    {
        if (address(converter) != address(0)) _addToken(ybvToken, true); // Removal must be done separately

        converters[ybvToken] = converter;
        emit ConverterAdded(ybvToken, converter);
    }

    /// @dev Add a new Pool for a Series, or replace an existing one for a new one.
    /// There can be only one Pool per Series. Until a Pool is added, it is not possible to borrow Base.
    function addPool(bytes6 seriesId, IPool pool)
        external
        auth
    {
        IFYToken fyToken = getSeries(seriesId).fyToken;
        require (fyToken == pool.fyToken(), "Mismatched pool fyToken and series");

        IERC20 ybvToken = pool.base(); // For ERC4626
        IConverter converter = getConverter(address(ybvToken)); // Without the converter, we don't add the pool
        // The converter acts as a bridge interface for all YBVToken methods, including the underlying address.
        require (fyToken.underlying() == address(converter.asset()), "Mismatched pool base and series");
        pools[seriesId] = pool;

        bool set = (pool != IPool(address(0))) ? true : false;
        _addToken(address(fyToken), set);
        _addToken(address(pool), set);
        _addIntegration(address(pool), set);

        emit PoolAdded(seriesId, address(pool));
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    /// Borrow only before maturity.
    function _pour(bytes12 vaultId, DataTypes.Vault memory vault, address to, int128 ink, int128 art)
        private
    {
        DataTypes.Series memory series;
        if (art != 0) series = getSeries(vault.seriesId);

        int128 fee;
        if (art > 0 && vault.ilkId != series.baseId && borrowingFee != 0)
            fee = ((series.maturity - block.timestamp) * uint256(int256(art)).wmul(borrowingFee)).i128();

        // Update accounting
        cauldron.pour(vaultId, ink, art + fee);

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            if (ink > 0) ilkJoin.join(vault.owner, uint128(ink));
            if (ink < 0) ilkJoin.exit(to, uint128(-ink));
        }

        // Manage debt tokens
        if (art != 0) {
            if (art > 0) series.fyToken.mint(to, uint128(art));
            else series.fyToken.burn(msg.sender, uint128(-art));
        }
    }

    /// @dev Add collateral and borrow from vault, so that a precise amount of base is obtained by the user.
    /// The base is obtained by borrowing fyToken and buying base with it in a pool.
    /// Only before maturity.
    function serve(bytes12 vaultId_, address to, uint128 ink, uint128 base, uint128 max)
        external payable
        returns (uint128 art)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        IPool pool = getPool(vault.seriesId);
        IConverter converter = getConverter(address(pool.base()));

        uint256 wrappedAmount = converter.wrappedFor(base);                // Find out how many wrapped tokens we need to buy, so that when unwrapped we get `base`
        art = pool.buyBase(address(converter), wrappedAmount.u128(), max); // The return value of `buyBase` is in fyToken, so it's the actual debt
        converter.unwrap(to);
        _pour(vaultId, vault, address(pool), ink.i128(), art.i128());      // Both pool and converter must not be a reentrancy risk
    }

    /// @dev Change series and debt of a vault.
    function roll(bytes12 vaultId_, bytes6 newSeriesId, uint8 loan, uint128 max)
        external payable
        returns (DataTypes.Vault memory vault, uint128 newDebt)
    {
        (, vault) = getVault(vaultId_);
        DataTypes.Balances memory balances = cauldron.balances(vaultId_);
        DataTypes.Series memory newSeries = getSeries(newSeriesId);
        
        {
            IPool pool = getPool(newSeriesId);
            IFYToken fyToken = IFYToken(newSeries.fyToken);

            // Calculate debt in base terms
            uint128 base = cauldron.debtToBase(vault.seriesId, balances.art);

            {
                IConverter converter = getConverter(address(pool.base()));
                IJoin baseJoin = getJoin(getSeries(vault.seriesId).baseId);

                // Convert base debt to ybvToken debt
                converter = getConverter(address(pool.base()));

                uint256 wrappedAmount = converter.wrappedFor(base);            // This is how many wrapped tokens we have to buy so that when unwrapped they pay off the existing debt.

                // Mint fyToken to the pool, as a kind of flash loan
                fyToken.mint(address(pool), wrappedAmount * loan);             // Loan is the size of the flash loan relative to the debt amount, 2 should be safe most of the time

                // Buy the base required to pay off the debt in series 1, and find out the debt in series 2
                newDebt = pool.buyBase(address(baseJoin), wrappedAmount.u128(), max); // new debt is in fyTokens of the new series

                converter.unwrap(address(baseJoin));                           // The converter must unwrap ybvTokens exactly into base
                baseJoin.join(address(baseJoin), base);                        // Repay the old series debt
            }

            pool.retrieveFYToken(address(fyToken));                        // Get the surplus fyToken
            fyToken.burn(address(fyToken), (base * loan) - newDebt);       // Burn the surplus
        }

        if (vault.ilkId != newSeries.baseId && borrowingFee != 0)
            newDebt += ((newSeries.maturity - block.timestamp) * uint256(newDebt).wmul(borrowingFee)).u128();  // Add borrowing fee, also stops users form rolling to a mature series

        (vault,) = cauldron.roll(vaultId_, newSeriesId, newDebt.i128() - balances.art.i128()); // Change the series and debt for the vault

        return (vault, newDebt);
    }
}