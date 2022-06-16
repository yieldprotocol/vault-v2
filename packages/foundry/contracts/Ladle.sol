// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/IOracle.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC2612.sol";
import "dss-interfaces/src/dss/DaiAbstract.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol";
import "./LadleStorage.sol";


/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract Ladle is LadleStorage, AccessControl() {
    using WMul for uint256;
    using CastU256U128 for uint256;
    using CastU256I128 for uint256;
    using CastU128I128 for uint128;
    using TransferHelper for IERC20;
    using TransferHelper for address payable;

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
    function addIntegration(address integration, bool set)
        external
        auth
    {
        _addIntegration(integration, set);
    }

    /// @dev Add or remove an integration.
    function _addIntegration(address integration, bool set)
        private
    {
        integrations[integration] = set;
        emit IntegrationAdded(integration, set);
    }

    /// @dev Add or remove a token that the Ladle can call `transfer` or `permit` on.
    function addToken(address token, bool set)
        external
        auth
    {
        _addToken(token, set);
    }
    

    /// @dev Add or remove a token that the Ladle can call `transfer` or `permit` on.
    function _addToken(address token, bool set)
        private
    {
        tokens[token] = set;
        emit TokenAdded(token, set);
    }


    /// @dev Add a new Join for an Asset, or replace an existing one for a new one.
    /// There can be only one Join per Asset. Until a Join is added, no tokens of that Asset can be posted or withdrawn.
    function addJoin(bytes6 assetId, IJoin join)
        external
        auth
    {
        address asset = cauldron.assets(assetId);
        require (asset != address(0), "Asset not found");
        require (join.asset() == asset, "Mismatched asset and join");
        joins[assetId] = join;

        bool set = (join != IJoin(address(0))) ? true : false;
        _addToken(asset, set);                  // address(0) disables the token
        emit JoinAdded(assetId, address(join));
    }

    /// @dev Add a new Pool for a Series, or replace an existing one for a new one.
    /// There can be only one Pool per Series. Until a Pool is added, it is not possible to borrow Base.
    function addPool(bytes6 seriesId, IPool pool)
        external
        auth
    {
        IFYToken fyToken = getSeries(seriesId).fyToken;
        require (fyToken == pool.fyToken(), "Mismatched pool fyToken and series");
        require (fyToken.underlying() == address(pool.base()), "Mismatched pool base and series");
        pools[seriesId] = pool;

        bool set = (pool != IPool(address(0))) ? true : false;
        _addToken(address(fyToken), set);       // address(0) disables the token
        _addToken(address(pool), set);          // address(0) disables the token
        _addIntegration(address(pool), set);    // address(0) disables the integration

        emit PoolAdded(seriesId, address(pool));
    }

    /// @dev Add or remove a module.
    /// @notice Treat modules as you would Ladle upgrades. Modules have unrestricted access to the Ladle
    /// storage, and can wreak havoc easily.
    /// Modules must not do any changes to any vault (owner, seriesId, ilkId) because of vault caching.
    /// Modules must not be contracts that can self-destruct because of `moduleCall`.
    /// Modules can't use `msg.value` because of `batch`.
    function addModule(address module, bool set)
        external
        auth
    {
        modules[module] = set;
        emit ModuleAdded(module, set);
    }

    /// @dev Set the fee parameter
    function setFee(uint256 fee)
        external
        auth
    {
        borrowingFee = fee;
        emit FeeSet(fee);
    }

    // ---- Call management ----

    /// @dev Allows batched call to self (this contract).
    /// @param calls An array of inputs for each call.
    function batch(bytes[] calldata calls) external payable returns(bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
            results[i] = result;
        }

        // build would have populated the cache, this deletes it
        cachedVaultId = bytes12(0);
    }

    /// @dev Allow users to route calls to a contract, to be used with batch
    function route(address integration, bytes calldata data)
        external payable
        returns (bytes memory result)
    {
        require(integrations[integration], "Unknown integration");
        return router.route(integration, data);
    }

    /// @dev Allow users to use functionality coded in a module, to be used with batch
    function moduleCall(address module, bytes calldata data)
        external payable
        returns (bytes memory result)
    {
        require (modules[module], "Unregistered module");
        bool success;
        (success, result) = module.delegatecall(data);
        if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
    }

    // ---- Token management ----

    /// @dev Execute an ERC2612 permit for the selected token
    function forwardPermit(IERC2612 token, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external payable
    {
        require(tokens[address(token)], "Unknown token");
        token.permit(msg.sender, spender, amount, deadline, v, r, s);
    }

    /// @dev Execute a Dai-style permit for the selected token
    function forwardDaiPermit(DaiAbstract token, address spender, uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s)
        external payable
    {
        require(tokens[address(token)], "Unknown token");
        token.permit(msg.sender, spender, nonce, deadline, allowed, v, r, s);
    }

    /// @dev Allow users to trigger a token transfer from themselves to a receiver through the ladle, to be used with batch
    function transfer(IERC20 token, address receiver, uint128 wad)
        external payable
    {
        require(tokens[address(token)], "Unknown token");
        token.safeTransferFrom(msg.sender, receiver, wad);
    }

    /// @dev Retrieve any token in the Ladle
    function retrieve(IERC20 token, address to) 
        external payable
        returns (uint256 amount)
    {
        require(tokens[address(token)], "Unknown token");
        amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);
    }

    /// @dev The WETH9 contract will send ether to BorrowProxy on `weth.withdraw` using this function.
    receive() external payable {
        require (msg.sender == address(weth), "Only receive from WETH");
    }

    /// @dev Accept Ether, wrap it and forward it to the WethJoin
    /// This function should be called first in a batch, and the Join should keep track of stored reserves
    /// Passing the id for a join that doesn't link to a contract implemnting IWETH9 will fail
    function joinEther(bytes6 etherId)
        external payable
        returns (uint256 ethTransferred)
    {
        ethTransferred = address(this).balance;
        IJoin wethJoin = getJoin(etherId);
        weth.deposit{ value: ethTransferred }();
        IERC20(address(weth)).safeTransfer(address(wethJoin), ethTransferred);
    }

    /// @dev Unwrap Wrapped Ether held by this Ladle, and send the Ether
    /// This function should be called last in a batch, and the Ladle should have no reason to keep an WETH balance
    function exitEther(address payable to)
        external payable
        returns (uint256 ethTransferred)
    {
        ethTransferred = weth.balanceOf(address(this));
        weth.withdraw(ethTransferred);
        to.safeTransferETH(ethTransferred);
    }

    // ---- Vault management ----

    /// @dev Generate a vaultId. A keccak256 is cheaper than using a counter with a SSTORE, even accounting for eventual collision retries.
    function _generateVaultId(uint8 salt) private view returns (bytes12) {
        return bytes12(keccak256(abi.encodePacked(msg.sender, block.timestamp, salt)));
    }

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(bytes6 seriesId, bytes6 ilkId, uint8 salt)
        external virtual payable
        returns(bytes12, DataTypes.Vault memory)
    {
        return _build(seriesId, ilkId, salt);
    }

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function _build(bytes6 seriesId, bytes6 ilkId, uint8 salt)
        internal
        returns(bytes12 vaultId, DataTypes.Vault memory vault)
    {
        vaultId = _generateVaultId(salt);
        while (cauldron.vaults(vaultId).seriesId != bytes6(0)) vaultId = _generateVaultId(++salt); // If the vault exists, generate other random vaultId
        vault = cauldron.build(msg.sender, vaultId, seriesId, ilkId);
        // Store the vault data in the cache
        cachedVaultId = vaultId;
    }

    /// @dev Change a vault series or collateral.
    function tweak(bytes12 vaultId_, bytes6 seriesId, bytes6 ilkId)
        external payable
        returns(DataTypes.Vault memory vault)
    {
        (bytes12 vaultId, ) = getVault(vaultId_); // getVault verifies the ownership as well
        // tweak checks that the series and the collateral both exist and that the collateral is approved for the series
        vault = cauldron.tweak(vaultId, seriesId, ilkId);
    }

    /// @dev Give a vault to another user.
    function give(bytes12 vaultId_, address receiver)
        external payable
        returns(DataTypes.Vault memory vault)
    {
        (bytes12 vaultId, ) = getVault(vaultId_);
        vault = cauldron.give(vaultId, receiver);
    }

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId_)
        external payable
    {
        (bytes12 vaultId, ) = getVault(vaultId_);
        cauldron.destroy(vaultId);
    }

    // ---- Asset and debt management ----

    /// @dev Move collateral and debt between vaults.
    function stir(bytes12 from, bytes12 to, uint128 ink, uint128 art)
        external payable
    {
        if (ink > 0) require (cauldron.vaults(from).owner == msg.sender, "Only origin vault owner");
        if (art > 0) require (cauldron.vaults(to).owner == msg.sender, "Only destination vault owner");
        cauldron.stir(from, to, ink, art);
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

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    /// Borrow only before maturity.
    function pour(bytes12 vaultId_, address to, int128 ink, int128 art)
        external payable
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        _pour(vaultId, vault, to, ink, art);
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
        
        art = pool.buyBase(to, base, max);
        _pour(vaultId, vault, address(pool), ink.i128(), art.i128());
    }

    /// @dev Repay vault debt using underlying token at a 1:1 exchange rate, without trading in a pool.
    /// It can add or remove collateral at the same time.
    /// The debt to repay is denominated in fyToken, even if the tokens pulled from the user are underlying.
    /// The debt to repay must be entered as a negative number, as with `pour`.
    /// Debt cannot be acquired with this function.
    function close(bytes12 vaultId_, address to, int128 ink, int128 art)
        external payable
        returns (uint128 base)
    {
        require (art < 0, "Only repay debt");                                          // When repaying debt in `frob`, art is a negative value. Here is the same for consistency.

        // Calculate debt in fyToken terms
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        base = cauldron.debtToBase(vault.seriesId, uint128(-art));

        // Update accounting
        cauldron.pour(vaultId, ink, art);

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            if (ink > 0) ilkJoin.join(vault.owner, uint128(ink));
            if (ink < 0) ilkJoin.exit(to, uint128(-ink));
        }

        // Manage underlying
        IJoin baseJoin = getJoin(series.baseId);
        baseJoin.join(msg.sender, base);
    }

    /// @dev Repay debt by selling base in a pool and using the resulting fyToken
    /// The base tokens need to be already in the pool, unaccounted for.
    /// Only before maturity. After maturity use close.
    function repay(bytes12 vaultId_, address to, int128 ink, uint128 min)
        external payable
        returns (uint128 art)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        IPool pool = getPool(vault.seriesId);

        art = pool.sellBase(address(series.fyToken), min);
        _pour(vaultId, vault, to, ink, -(art.i128()));
    }

    /// @dev Repay all debt in a vault by buying fyToken from a pool with base.
    /// The base tokens need to be already in the pool, unaccounted for. The surplus base will be returned to msg.sender.
    /// Only before maturity. After maturity use close.
    function repayVault(bytes12 vaultId_, address to, int128 ink, uint128 max)
        external payable
        returns (uint128 base)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        IPool pool = getPool(vault.seriesId);

        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        base = pool.buyFYToken(address(series.fyToken), balances.art, max);
        _pour(vaultId, vault, to, ink, -(balances.art.i128()));
        pool.retrieveBase(msg.sender);
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

            // Calculate debt in fyToken terms
            uint128 base = cauldron.debtToBase(vault.seriesId, balances.art);

            // Mint fyToken to the pool, as a kind of flash loan
            fyToken.mint(address(pool), base * loan);                // Loan is the size of the flash loan relative to the debt amount, 2 should be safe most of the time

            // Buy the base required to pay off the debt in series 1, and find out the debt in series 2
            newDebt = pool.buyBase(address(baseJoin), base, max);
            baseJoin.join(address(baseJoin), base);                  // Repay the old series debt

            pool.retrieveFYToken(address(fyToken));                 // Get the surplus fyToken
            fyToken.burn(address(fyToken), (base * loan) - newDebt);    // Burn the surplus
        }

        if (vault.ilkId != newSeries.baseId && borrowingFee != 0)
            newDebt += ((newSeries.maturity - block.timestamp) * uint256(newDebt).wmul(borrowingFee)).u128();  // Add borrowing fee, also stops users form rolling to a mature series

        (vault,) = cauldron.roll(vaultId, newSeriesId, newDebt.i128() - balances.art.i128()); // Change the series and debt for the vault

        return (vault, newDebt);
    }

    // ---- Ladle as a token holder ----

    /// @dev Use fyToken in the Ladle to repay debt. Return unused fyToken to `to`.
    /// Return as much collateral as debt was repaid, as well. This function is only used when
    /// removing liquidity added with "Borrow and Pool", so it's safe to assume the exchange rate
    /// is 1:1. If used in other contexts, it might revert, which is fine.
    function repayFromLadle(bytes12 vaultId_, address to)
        external payable
        returns (uint256 repaid)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        
        uint256 amount = series.fyToken.balanceOf(address(this));
        repaid = amount <= balances.art ? amount : balances.art;

        // Update accounting, burn fyToken and return collateral
        if (repaid > 0) {
            cauldron.pour(vaultId, -(repaid.i128()), -(repaid.i128()));
            series.fyToken.burn(address(this), repaid);
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.exit(to, repaid.u128());
        }

        // Return remainder
        if (amount - repaid > 0) IERC20(address(series.fyToken)).safeTransfer(to, amount - repaid);
    }

    /// @dev Use base in the Ladle to repay debt. Return unused base to `to`.
    /// Return as much collateral as debt was repaid, as well. This function is only used when
    /// removing liquidity added with "Borrow and Pool", so it's safe to assume the exchange rate
    /// is 1:1. If used in other contexts, it might revert, which is fine.
    function closeFromLadle(bytes12 vaultId_, address to)
        external payable
        returns (uint256 repaid)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        
        IERC20 base = IERC20(cauldron.assets(series.baseId));
        uint256 amount = base.balanceOf(address(this));
        uint256 debtInBase = cauldron.debtToBase(vault.seriesId, balances.art);
        uint128 repaidInBase = ((amount <= debtInBase) ? amount : debtInBase).u128();
        repaid = (repaidInBase == debtInBase) ? balances.art : cauldron.debtFromBase(vault.seriesId, repaidInBase);

        // Update accounting, join base and return collateral
        if (repaidInBase > 0) {
            cauldron.pour(vaultId, -(repaid.i128()), -(repaid.i128()));
            IJoin baseJoin = getJoin(series.baseId);
            base.safeTransfer(address(baseJoin), repaidInBase);
            baseJoin.join(address(this), repaidInBase);
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.exit(to, repaid.u128()); // repaid is the ink collateral released, and equal to the fyToken debt. repaidInBase is the value of the fyToken debt in base terms
        }

        // Return remainder
        if (amount - repaidInBase > 0) base.safeTransfer(to, amount - repaidInBase);
    }

    /// @dev Allow users to redeem fyToken, to be used with batch.
    /// If 0 is passed as the amount to redeem, it redeems the fyToken balance of the Ladle instead.
    function redeem(bytes6 seriesId, address to, uint256 wad)
        external payable
        returns (uint256)
    {
        IFYToken fyToken = getSeries(seriesId).fyToken;
        return fyToken.redeem(to, wad != 0 ? wad : fyToken.balanceOf(address(this)));
    }

}