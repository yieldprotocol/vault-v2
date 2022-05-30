// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol";
import "./LadleStorage.sol";


/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract LadleTV is LadleStorage, AccessControl() {
    using WMul for uint256;
    using CastU256U128 for uint256;
    using CastU256I128 for uint256;
    using CastU128I128 for uint128;
    using TransferHelper for IERC20;
    using TransferHelper for address payable;

    event ConverterAdded(address indexed asset, IConverter indexed converter);

    mapping (address => IConverter) public converters; // Converter contracts between a Yield-Bearing Vault and its underlying.

    constructor (ICauldron cauldron, IWETH9 weth) LadleStorage(cauldron, weth) { }

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
        emit ConverterAdded(ybvToken, address(converter));
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

    /// @dev Add collateral and borrow from vault, so that a precise amount of base is obtained by the user.
    /// The base is obtained by borrowing fyToken and buying base with it in a pool.
    /// Only before maturity.
    function serve(bytes12 vaultId_, address to, uint128 ink, uint128 base, uint128 max)
        external payable
        returns (uint128 art)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        IPool pool = getPool(vault.seriesId);
        
        converter = getConverter(address(pool.base()));
        ybvTokens = converter.wrappedFor(baseAmount); // Find out how many ybvTokens we need to buy, so that when unwrapped we get `base`
        art = pool.buyBase(address(converter), ybvTokens, max); // The return value of `buyBase` is in fyToken, so it's the actual debt
        converter.unwrap(to);
        _pour(vaultId, vault, address(pool), ink.i128(), art.si128()); // Both pool and converter must not be a reentrancy risk
    }

    /// @dev Change series and debt of a vault.
    function roll(bytes12 vaultId_, bytes6 newSeriesId, uint8 loan, uint128 max)
        external payable
        returns (DataTypes.Vault memory vault, uint128 newDebt)
    {
        bytes12 vaultId;
        (vaultId, vault) = getVault(vaultId_);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        DataTypes.Series memory newSeries = getSeries(newSeriesId);
        
        {
            IPool pool = getPool(newSeriesId);
            IFYToken fyToken = IFYToken(newSeries.fyToken);
            IJoin baseJoin = getJoin(series.baseId);

            // Calculate debt in base terms
            uint128 base = cauldron.debtToBase(vault.seriesId, balances.art);

            // Convert base debt to ybvToken debt
            converter = getConverter(address(pool.base()));
            ybvTokens = converter.wrappedFor(base);                       // This is how many ybvTokens we have to buy so that when unwrapped they pay off the existing debt.

            // Mint fyToken to the pool, as a kind of flash loan
            fyToken.mint(address(pool), ybvTokens * loan);                // Loan is the size of the flash loan relative to the debt amount, 2 should be safe most of the time

            // Buy the base required to pay off the debt in series 1, and find out the debt in series 2
            newDebt = pool.buyBase(address(baseJoin), ybvTokens, max);    // new debt is in fyTokens of the new series
            converter.unwrap(address(baseJoin));                          // The converter must unwrap ybvTokens exactly into base
            baseJoin.join(address(baseJoin), base);                       // Repay the old series debt

            pool.retrieveFYToken(address(fyToken));                       // Get the surplus fyToken
            fyToken.burn(address(fyToken), (base * loan) - newDebt);      // Burn the surplus
        }

        if (vault.ilkId != newSeries.baseId && borrowingFee != 0)
            newDebt += ((newSeries.maturity - block.timestamp) * uint256(newDebt).wmul(borrowingFee)).u128();  // Add borrowing fee, also stops users form rolling to a mature series

        (vault,) = cauldron.roll(vaultId, newSeriesId, newDebt.i128() - balances.art.i128()); // Change the series and debt for the vault

        return (vault, newDebt);
    }
}