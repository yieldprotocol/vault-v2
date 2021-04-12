// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "@yield-protocol/utils/contracts/token/IERC2612.sol";
import "dss-interfaces/src/dss/DaiAbstract.sol";
import "@yield-protocol/utils-v2/contracts/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/Multicall.sol";
import "@yield-protocol/utils-v2/contracts/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/IWETH9.sol";


library DMath { // Fixed point arithmetic in 6 decimal units
    /// @dev Multiply an amount by a fixed point factor with 6 decimals, returning an amount
    function dmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            uint256 _z = uint256(x) * uint256(y) / 1e6;
            require (_z <= type(uint128).max, "DMUL Overflow");
            z = uint128(_z);
        }
    }
}

library Safe128 {
    /// @dev Safely cast an uint128 to an int128
    function i128(uint128 x) internal pure returns (int128 y) {
        require (x <= uint128(type(int128).max), "Cast overflow");
        y = int128(x);
    }
}

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract Ladle is AccessControl(), Multicall {
    using DMath for uint128;
    using Safe128 for uint128;
    using TransferHelper for IERC20;
    using TransferHelper for address payable;

    enum Operation {
        BUILD,               // 0
        STIR_TO,             // 1
        STIR_FROM,           // 2
        POUR,                // 3
        SERVE,               // 4
        CLOSE,               // 5
        REPAY,               // 6
        REPAY_VAULT,         // 7
        FORWARD_PERMIT,      // 8
        FORWARD_DAI_PERMIT,  // 9
        JOIN_ETHER,          // 10
        EXIT_ETHER,          // 11
        TRANSFER_TO_POOL,    // 12
        RETRIEVE_FROM_POOL,  // 13
        ROUTE,               // 14
        TRANSFER_TO_FYTOKEN, // 15
        REDEEM               // 16
    }

    ICauldron public cauldron;
    address public poolRouter;

    mapping (bytes6 => IJoin)                   public joins;            // Join contracts available to manage assets. The same Join can serve multiple assets (ETH-A, ETH-B, etc...)
    mapping (bytes6 => IPool)                   public pools;            // Pool contracts available to manage series. 12 bytes still free.

    event JoinAdded(bytes6 indexed assetId, address indexed join);
    event PoolAdded(bytes6 indexed seriesId, address indexed pool);
    event PoolRouterSet(address indexed poolRouter);

    constructor (ICauldron cauldron_) {
        cauldron = cauldron_;
    }

    // ---- Data sourcing ----
    /// @dev Obtains a vault by vaultId from the Cauldron, and verifies that msg.sender is the owner
    function getOwnedVault(bytes12 vaultId)
        internal view returns(DataTypes.Vault memory vault)
    {
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
        require (fyToken.asset() == address(pool.baseToken()), "Mismatched pool base and series");
        pools[seriesId] = pool;
        emit PoolAdded(seriesId, address(pool));
    }

    /// @dev Set the Pool Router for this Ladle
    function setPoolRouter(address poolRouter_)
        external
        auth
    {
        poolRouter = poolRouter_;
        emit PoolRouterSet(poolRouter_);
    }

    // ---- Batching ----


    /// @dev Submit a series of calls for execution.
    /// Unlike `multicall`, this function calls private functions, saving a CALL per function.
    /// It also caches the vault, which is useful in `build` + `pour` and `build` + `serve` combinations.
    function batch(
        bytes12 vaultId,
        Operation[] calldata operations,
        bytes[] calldata data
    ) external payable {    // TODO: I think we need `payable` to receive ether which we will deposit through `joinEther`
        require(operations.length == data.length, "Unmatched operation data");
        DataTypes.Vault memory vault;
        IFYToken fyToken;
        IPool pool;

        // Unless we are building the vault, we cache it
        if (operations[0] != Operation.BUILD) vault = getOwnedVault(vaultId);

        // Execute all operations in the batch. Conditionals ordered by expected frequency.
        for (uint256 i = 0; i < operations.length; i += 1) {
            Operation operation = operations[i];

            if (operation == Operation.BUILD) {
                (bytes6 seriesId, bytes6 ilkId) = abi.decode(data[i], (bytes6, bytes6));
                vault = _build(vaultId, seriesId, ilkId);   // Cache the vault that was just built
            
            } else if (operation == Operation.FORWARD_PERMIT) {
                (bytes6 id, bool asset, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
                    abi.decode(data[i], (bytes6, bool, address, uint256, uint256, uint8, bytes32, bytes32));
                _forwardPermit(id, asset, spender, amount, deadline, v, r, s);
            
            } else if (operation == Operation.JOIN_ETHER) {
                (bytes6 etherId) = abi.decode(data[i], (bytes6));
                _joinEther(etherId);
            
            } else if (operation == Operation.POUR) {
                (address to, int128 ink, int128 art) = abi.decode(data[i], (address, int128, int128));
                _pour(vaultId, vault, to, ink, art);
            
            } else if (operation == Operation.SERVE) {
                (address to, uint128 ink, uint128 base, uint128 max) = abi.decode(data[i], (address, uint128, uint128, uint128));
                _serve(vaultId, vault, to, ink, base, max);
            
            } else if (operation == Operation.FORWARD_DAI_PERMIT) {
                (bytes6 id, bool asset, address spender, uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s) =
                    abi.decode(data[i], (bytes6, bool, address, uint256, uint256, bool, uint8, bytes32, bytes32));
                _forwardDaiPermit(id, asset, spender, nonce, deadline, allowed, v, r, s);
            
            } else if (operation == Operation.TRANSFER_TO_POOL) {
                (bool base, uint128 wad) =
                    abi.decode(data[i], (bool, uint128));
                if (address(pool) == address(0)) pool = getPool(vault.seriesId);
                _transferToPool(pool, base, wad);
            
            } else if (operation == Operation.RETRIEVE_FROM_POOL) {
                (bool base, address to) =
                    abi.decode(data[i], (bool, address));
                if (address(pool) == address(0)) pool = getPool(vault.seriesId);
                _retrieveFromPool(pool, base, to);
            
            } else if (operation == Operation.ROUTE) {
                _route(data[i]);
            
            } else if (operation == Operation.EXIT_ETHER) {
                (bytes6 etherId, address to) = abi.decode(data[i], (bytes6, address));
                _exitEther(etherId, payable(to));
            
            } else if (operation == Operation.CLOSE) {
                (address to, int128 ink, int128 art) = abi.decode(data[i], (address, int128, int128));
                _close(vaultId, vault, to, ink, art);
            
            } else if (operation == Operation.REPAY) {
                (address to, int128 ink, uint128 min) = abi.decode(data[i], (address, int128, uint128));
                _repay(vaultId, vault, to, ink, min);
            
            } else if (operation == Operation.REPAY_VAULT) {
                (address to, int128 ink, uint128 max) = abi.decode(data[i], (address, int128, uint128));
                _repayVault(vaultId, vault, to, ink, max);
            
            } else if (operation == Operation.TRANSFER_TO_FYTOKEN) {
                (uint256 amount) = abi.decode(data[i], (uint256));
                if (address(fyToken) == address(0)) fyToken = getSeries(vault.seriesId).fyToken;
                _transferToFYToken(fyToken, amount);
            
            } else if (operation == Operation.REDEEM) {
                (address to, uint256 amount) = abi.decode(data[i], (address, uint256));
                if (address(fyToken) == address(0)) fyToken = getSeries(vault.seriesId).fyToken;
                _redeem(fyToken, to, amount);
            
            } else if (operation == Operation.STIR_FROM) {
                (bytes12 to, uint128 ink, uint128 art) = abi.decode(data[i], (bytes12, uint128, uint128));
                _stirFrom(vaultId, to, ink, art);
            
            } else if (operation == Operation.STIR_TO) {
                (bytes12 from, uint128 ink, uint128 art) = abi.decode(data[i], (bytes12, uint128, uint128));
                _stirTo(from, vaultId, ink, art);
            
            } else {
                revert("Invalid operation");
            }
        }
    }

    // ---- Vault management ----

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        external payable
        returns(DataTypes.Vault memory vault)
    {
        return _build(vaultId, seriesId, ilkId);
    }

    /// @dev Change a vault series or collateral.
    function tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        external payable
        returns(DataTypes.Vault memory vault)
    {
        getOwnedVault(vaultId);
        // tweak checks that the series and the collateral both exist and that the collateral is approved for the series
        return cauldron.tweak(vaultId, seriesId, ilkId);
    }

    /// @dev Give a vault to another user.
    function give(bytes12 vaultId, address receiver)
        external payable
        returns(DataTypes.Vault memory vault)
    {
        getOwnedVault(vaultId);
        return cauldron.give(vaultId, receiver);
    }

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId)
        external payable
    {
        getOwnedVault(vaultId);
        cauldron.destroy(vaultId);
    }

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function _build(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        private
        returns(DataTypes.Vault memory vault)
    {
        return cauldron.build(msg.sender, vaultId, seriesId, ilkId);
    }

    // ---- Asset and debt management ----

    /// @dev Move collateral and debt between vaults.
    function stir(bytes12 from, bytes12 to, uint128 ink, uint128 art)
        external payable
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        if (ink > 0) require (cauldron.vaults(from).owner == msg.sender, "Only origin vault owner");
        if (art > 0) require (cauldron.vaults(to).owner == msg.sender, "Only destination vault owner");
        return cauldron.stir(from, to, ink, art);
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    function pour(bytes12 vaultId, address to, int128 ink, int128 art)
        external payable
        returns (DataTypes.Balances memory balances)
    {
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        balances = _pour(vaultId, vault, to, ink, art);
    }

    /// @dev Add collateral and borrow from vault, so that a precise amount of base is obtained by the user.
    /// The base is obtained by borrowing fyToken and buying base with it in a pool.
    function serve(bytes12 vaultId, address to, uint128 ink, uint128 base, uint128 max)
        external payable
        returns (DataTypes.Balances memory balances, uint128 art)
    {
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        (balances, art) = _serve(vaultId, vault, to, ink, base, max);
    }

    /// @dev Repay vault debt using underlying token at a 1:1 exchange rate, without trading in a pool.
    /// It can add or remove collateral at the same time.
    /// The debt to repay is denominated in fyToken, even if the tokens pulled from the user are underlying.
    /// The debt to repay must be entered as a negative number, as with `pour`.
    /// Debt cannot be acquired with this function.
    function close(bytes12 vaultId, address to, int128 ink, int128 art)
        external payable
        returns (DataTypes.Balances memory balances)
    {
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        balances = _close(vaultId, vault, to, ink, art);
    }

    /// @dev Repay debt by selling base in a pool and using the resulting fyToken
    /// The base tokens need to be already in the pool, unaccounted for.
    function repay(bytes12 vaultId, address to, int128 ink, uint128 min)
        external payable
        returns (DataTypes.Balances memory balances, uint128 art)
    {
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        (balances, art) = _repay(vaultId, vault, to, ink, min);
    }

    /// @dev Repay all debt in a vault by buying fyToken from a pool with base.
    /// The base tokens need to be already in the pool, unaccounted for. The surplus base needs to be retrieved from the pool.
    function repayVault(bytes12 vaultId, address to, int128 ink, uint128 max)
        external payable
        returns (DataTypes.Balances memory balances, uint128 base)
    {
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        (balances, base) = _repayVault(vaultId, vault, to, ink, max);
    }

    /// @dev Change series and debt of a vault.
    function roll(bytes12 vaultId, bytes6 seriesId, int128 art)
        external payable
        returns (uint128)
    {
        getOwnedVault(vaultId);
        // TODO: Buy underlying in the pool for the new series, and sell it in pool for the old series.
        // The new debt will be the amount of new series fyToken sold. This fyToken will be minted into the new series pool.
        // The amount obtained when selling the underlying must produce the exact amount to repay the existing debt. The old series fyToken amount will be burnt.
        
        return cauldron.roll(vaultId, seriesId, art);
    }

    /// @dev Move collateral and debt to the owner's vault.
    function _stirTo(bytes12 from, bytes12 to, uint128 ink, uint128 art)
        private
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        if (ink > 0) require (cauldron.vaults(from).owner == msg.sender, "Only origin vault owner");
        return cauldron.stir(from, to, ink, art);
    }

    /// @dev Move collateral and debt from the owner's vault.
    function _stirFrom(bytes12 from, bytes12 to, uint128 ink, uint128 art)
        private
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        if (art > 0) require (cauldron.vaults(to).owner == msg.sender, "Only destination vault owner");
        return cauldron.stir(from, to, ink, art);
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    function _pour(bytes12 vaultId, DataTypes.Vault memory vault, address to, int128 ink, int128 art)
        private
        returns (DataTypes.Balances memory balances)
    {
        // Update accounting
        balances = cauldron.pour(vaultId, ink, art);

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            if (ink > 0) ilkJoin.join(vault.owner, uint128(ink));
            if (ink < 0) ilkJoin.exit(to, uint128(-ink));
        }

        // Manage debt tokens
        if (art != 0) {
            DataTypes.Series memory series = getSeries(vault.seriesId);
            if (art > 0) series.fyToken.mint(to, uint128(art));
            else series.fyToken.burn(msg.sender, uint128(-art));
        }
    }

    /// @dev Add collateral and borrow from vault, so that a precise amount of base is obtained by the user.
    /// The base is obtained by borrowing fyToken and buying base with it in a pool.
    function _serve(bytes12 vaultId, DataTypes.Vault memory vault, address to, uint128 ink, uint128 base, uint128 max)
        private
        returns (DataTypes.Balances memory balances, uint128 art)
    {
        IPool pool = getPool(vault.seriesId);
        
        art = pool.buyBaseTokenPreview(base);
        balances = _pour(vaultId, vault, address(pool), ink.i128(), art.i128());
        pool.buyBaseToken(to, base, max);
    }

    /// @dev Repay vault debt using underlying token at a 1:1 exchange rate, without trading in a pool.
    /// It can add or remove collateral at the same time.
    /// The debt to repay is denominated in fyToken, even if the tokens pulled from the user are underlying.
    /// The debt to repay must be entered as a negative number, as with `pour`.
    /// Debt cannot be acquired with this function.
    function _close(bytes12 vaultId, DataTypes.Vault memory vault, address to, int128 ink, int128 art)
        private
        returns (DataTypes.Balances memory balances)
    {
        require (art < 0, "Only repay debt");                                          // When repaying debt in `frob`, art is a negative value. Here is the same for consistency.

        // Calculate debt in fyToken terms
        DataTypes.Series memory series = getSeries(vault.seriesId);
        bytes6 baseId = series.baseId;
        uint128 amt;
        if (uint32(block.timestamp) >= series.maturity) {
            IOracle rateOracle = cauldron.rateOracles(baseId);
            amt = uint128(-art).dmul(rateOracle.accrual(series.maturity));
        } else {
            amt = uint128(-art);
        }

        // Update accounting
        balances = cauldron.pour(vaultId, ink, art);

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            if (ink > 0) ilkJoin.join(vault.owner, uint128(ink));
            if (ink < 0) ilkJoin.exit(to, uint128(-ink));
        }

        // Manage underlying
        IJoin baseJoin = getJoin(series.baseId);
        baseJoin.join(msg.sender, amt);
    }

    /// @dev Repay debt by selling base in a pool and using the resulting fyToken
    /// The base tokens need to be already in the pool, unaccounted for.
    function _repay(bytes12 vaultId, DataTypes.Vault memory vault, address to, int128 ink, uint128 min)
        private
        returns (DataTypes.Balances memory balances, uint128 art)
    {
        DataTypes.Series memory series = getSeries(vault.seriesId);
        IPool pool = getPool(vault.seriesId);

        art = pool.sellBaseToken(address(series.fyToken), min);
        balances = _pour(vaultId, vault, to, ink, -(art.i128()));
    }

    /// @dev Repay all debt in a vault by buying fyToken from a pool with base.
    /// The base tokens need to be already in the pool, unaccounted for. The surplus base needs to be retrieved from the pool.
    function _repayVault(bytes12 vaultId, DataTypes.Vault memory vault, address to, int128 ink, uint128 max)
        private
        returns (DataTypes.Balances memory balances, uint128 base)
    {
        DataTypes.Series memory series = getSeries(vault.seriesId);
        IPool pool = getPool(vault.seriesId);

        balances = cauldron.balances(vaultId);
        base = pool.buyFYToken(address(series.fyToken), balances.art, max);
        balances = _pour(vaultId, vault, to, ink, -(balances.art.i128()));
    }

    // ---- Liquidations ----

    /// @dev Allow liquidation contracts to move assets to wind down vaults
    function settle(bytes12 vaultId, address user, uint128 ink, uint128 art)
        external
        auth
    {
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        DataTypes.Series memory series = getSeries(vault.seriesId);

        cauldron.slurp(vaultId, ink, art);                                                  // Remove debt and collateral from the vault

        if (ink != 0) {                                                                     // Give collateral to the user
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.exit(user, ink);
        }
        if (art != 0) {                                                                     // Take underlying from user
            IJoin baseJoin = getJoin(series.baseId);
            baseJoin.join(user, art);
        }
    }

    // ---- Permit management ----

    /// @dev Execute an ERC2612 permit for the selected asset or fyToken
    function forwardPermit(bytes6 id, bool asset, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external payable
    {
        _forwardPermit(id, asset, spender, amount, deadline, v, r, s);
    }

    /// @dev Execute a Dai-style permit for the selected asset or fyToken
    function forwardDaiPermit(bytes6 id, bool asset, address spender, uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s)
        external payable
    {
        _forwardDaiPermit(id, asset, spender, nonce, deadline, allowed, v, r, s);
    }

    /// @dev From an id, which can be an assetId or a seriesId, find the resulting asset or fyToken
    function findToken(bytes6 id, bool asset)
        private view returns (address token)
    {
        token = asset ? cauldron.assets(id) : address(getSeries(id).fyToken);
        require (token != address(0), "Token not found");
    }

    /// @dev Execute an ERC2612 permit for the selected asset or fyToken
    function _forwardPermit(bytes6 id, bool asset, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        private
    {
        IERC2612 token = IERC2612(findToken(id, asset));
        token.permit(msg.sender, spender, amount, deadline, v, r, s);
    }

    /// @dev Execute a Dai-style permit for the selected asset or fyToken
    function _forwardDaiPermit(bytes6 id, bool asset, address spender, uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s)
        private
    {
        DaiAbstract token = DaiAbstract(findToken(id, asset));
        token.permit(msg.sender, spender, nonce, deadline, allowed, v, r, s);
    }

    // ---- Ether management ----

    /// @dev The WETH9 contract will send ether to BorrowProxy on `weth.withdraw` using this function.
    receive() external payable { }

    /// @dev Accept Ether, wrap it and forward it to the WethJoin
    /// This function should be called first in a multicall, and the Join should keep track of stored reserves
    /// Passing the id for a join that doesn't link to a contract implemnting IWETH9 will fail
    function joinEther(bytes6 etherId)
        external payable
        returns (uint256 ethTransferred)
    {
        ethTransferred = _joinEther(etherId);
    }

    /// @dev Unwrap Wrapped Ether held by this Ladle, and send the Ether
    /// This function should be called last in a multicall, and the Ladle should have no reason to keep an WETH balance
    function exitEther(bytes6 etherId, address payable to)
        external payable
        returns (uint256 ethTransferred)
    {
        ethTransferred = _exitEther(etherId, to);
    }

    /// @dev Accept Ether, wrap it and forward it to the WethJoin
    /// This function should be called first in a multicall, and the Join should keep track of stored reserves
    /// Passing the id for a join that doesn't link to a contract implemnting IWETH9 will fail
    function _joinEther(bytes6 etherId)
        private
        returns (uint256 ethTransferred)
    {
        ethTransferred = address(this).balance;

        IJoin wethJoin = getJoin(etherId);
        address weth = wethJoin.asset();                    // TODO: Consider setting weth contract via governance

        IWETH9(weth).deposit{ value: ethTransferred }();   // TODO: Test gas savings using WETH10 `depositTo`
        IERC20(weth).safeTransfer(address(wethJoin), ethTransferred);
    }

    /// @dev Unwrap Wrapped Ether held by this Ladle, and send the Ether
    /// This function should be called last in a multicall, and the Ladle should have no reason to keep an WETH balance
    function _exitEther(bytes6 etherId, address payable to)
        private
        returns (uint256 ethTransferred)
    {
        IJoin wethJoin = getJoin(etherId);
        address weth = wethJoin.asset();            // TODO: Consider setting weth contract via governance
        ethTransferred = IERC20(weth).balanceOf(address(this));
        IWETH9(weth).withdraw(ethTransferred);   // TODO: Test gas savings using WETH10 `withdrawTo`
        to.safeTransferETH(ethTransferred); /// TODO: Consider reentrancy
    }

    // ---- Pool router ----

    /// @dev Allow users to trigger a token transfer to a pool through the ladle, to be used with multicall
    function transferToPool(bytes6 seriesId, bool base, uint128 wad)
        external payable
    {
        _transferToPool(getPool(seriesId), base, wad);
    }

    /// @dev Allow users to trigger a token transfer to a pool through the ladle, to be used with multicall
    function retrieveFromPool(bytes6 seriesId, bool base, address to)
        external payable
        returns (uint128 retrieved)
    {
        IPool pool = getPool(seriesId);
        retrieved = _retrieveFromPool(pool, base, to);
    }

    /// @dev Allow users to route calls to a pool, to be used with multicall
    function route(bytes memory data)
        external payable
        returns (bool success, bytes memory result)
    {
        (success, result) = _route(data);
    }

    /// @dev Allow users to trigger a token transfer to a pool through the ladle, to be used with batch
    function _transferToPool(IPool pool, bool base, uint128 wad)
        private
    {
        IERC20 token = base ? pool.baseToken() : pool.fyToken();
        token.safeTransferFrom(msg.sender, address(pool), wad);
    }
    
    /// @dev Allow users to trigger a token transfer to a pool through the ladle, to be used with batch
    function _retrieveFromPool(IPool pool, bool base, address to)
        private
        returns (uint128 retrieved)
    {
        retrieved = base ? pool.retrieveBaseToken(to) : pool.retrieveFYToken(to);
    }

    /// @dev Allow users to route calls to a pool, to be used with batch
    function _route(bytes memory data)
        private
        returns (bool success, bytes memory result)
    {
        (success, result) = poolRouter.call{ value: msg.value }(data);
        if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
    }

    // ---- FYToken router ----

    /// @dev Allow users to trigger a token transfer to a fyToken through the ladle, to be used with multicall
    function transferToFYToken(bytes6 seriesId, uint256 wad)
        external payable
    {
        _transferToFYToken(getSeries(seriesId).fyToken, wad);
    }

    /// @dev Allow users to redeem fyToken, to be used with multicall
    /// The fyToken needs to have been transferred to the FYToken contract
    function redeem(bytes6 seriesId, address to, uint256 wad)
        external payable
        returns (uint256)
    {

        return _redeem(getSeries(seriesId).fyToken, to, wad);
    }

    /// @dev Allow users to trigger a token transfer to a pool through the ladle, to be used with batch
    function _transferToFYToken(IFYToken fyToken, uint256 wad)
        private
    {
        IERC20(fyToken).safeTransferFrom(msg.sender, address(fyToken), wad);
    }

    /// @dev Allow users to redeem fyToken, to be used with batch
    function _redeem(IFYToken fyToken, address to, uint256 wad)
        private
        returns (uint256)
    {
        return fyToken.redeem(to, wad);
    }
}