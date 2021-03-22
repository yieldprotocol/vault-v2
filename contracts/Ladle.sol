// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "@yield-protocol/utils/contracts/token/IERC2612.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "./AccessControl.sol";
import "./Batchable.sol";
import "./IWETH9.sol";


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
contract Ladle is AccessControl(), Batchable {
    using RMath for uint128;

    ICauldron public cauldron;

    mapping (bytes6 => IJoin)                   public joins;            // Join contracts available to manage assets. The same Join can serve multiple assets (ETH-A, ETH-B, etc...)
    mapping (bytes6 => IPool)                   public pools;            // Pool contracts available to manage series. 12 bytes still free.

    event JoinAdded(bytes6 indexed assetId, address indexed join);
    event PoolAdded(bytes6 indexed seriesId, address indexed pool);

    constructor (ICauldron cauldron_) {
        cauldron = cauldron_;
    }

    /// @dev Add a new Join for an Asset, or replace an existing one for a new one.
    /// There can be only one Join per Asset. Until a Join is added, no tokens of that Asset can be posted or withdrawn.
    function addJoin(bytes6 assetId, IJoin join)
        external
        auth
    {
        require (cauldron.assets(assetId) != IERC20(address(0)), "Asset not found");
        joins[assetId] = join;
        // TODO: Assert the base address and join.token() match
        emit JoinAdded(assetId, address(join));
    }

    /// @dev Add a new Pool for a Series, or replace an existing one for a new one.
    /// There can be only one Pool per Series. Until a Pool is added, it is not possible to borrow Base.
    function addPool(bytes6 seriesId, IPool pool)
        external
        auth
    {
        require (cauldron.series(seriesId).fyToken != IFYToken(address(0)), "Series not found");    // 1 CALL + 1 SLOAD
        pools[seriesId] = pool;                                                          // 1 SSTORE
        // TODO: Assert the pool fyToken address and series fyToken address match
        emit PoolAdded(seriesId, address(pool));
    }

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        public payable
    {
        cauldron.build(msg.sender, vaultId, seriesId, ilkId);
    }

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId)
        public payable
    {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");
        cauldron.destroy(vaultId);
    }

    /// @dev Change a vault series or collateral.
    function tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId)
        public payable
    {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");
        // tweak checks that the series and the collateral both exist and that the collateral is approved for the series
        cauldron.tweak(vaultId, seriesId, ilkId);                                                  // Cost of `tweak`
    }

    /// @dev Give a vault to another user.
    function give(bytes12 vaultId, address receiver)
        public payable
    {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");
        cauldron.give(vaultId, receiver);                                                              // Cost of `give`
    }

    /// @dev Move collateral between vaults.
    function stir(bytes12 from, bytes12 to, uint128 ink)
        public payable
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        DataTypes.Vault memory vaultFrom = cauldron.vaults(from);                       // 1 CALL + 1 SLOAD
        require (vaultFrom.owner == msg.sender, "Only vault owner");
        DataTypes.Balances memory balancesFrom_;
        DataTypes.Balances memory balancesTo_;
        (balancesFrom_, balancesTo_) = cauldron.stir(from, to, ink);                              // Cost of `stir`
        return (balancesFrom_, balancesTo_);
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    function pour(bytes12 vaultId, address to, int128 ink, int128 art)
        public payable
        returns (DataTypes.Balances memory balances_)
    {
        // Verify vault ownership
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");

        // Update accounting
        balances_ = cauldron.pour(vaultId, ink, art);                                  // Cost of `cauldron.pour` call.

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin_ = joins[vault_.ilkId];
            require (ilkJoin_ != IJoin(address(0)), "Ilk join not found");
            if (ink > 0) ilkJoin_.join(vault_.owner, ink);
            if (ink < 0) ilkJoin_.join(to, ink);
        }

        // Manage debt tokens
        if (art != 0) {
            DataTypes.Series memory series_ = cauldron.series(vault_.seriesId);         // 1 CALL + 1 SLOAD
            // TODO: Consider checking the series exists
            if (art > 0) {
                require(uint32(block.timestamp) <= series_.maturity, "Mature");
                IFYToken(series_.fyToken).mint(to, uint128(art));               // 1 CALL(40) + fyToken.mint.
            } else {
                IFYToken(series_.fyToken).burn(msg.sender, uint128(-art));              // 1 CALL(40) + fyToken.burn.
            }
        }
    }

    /// @dev Repay vault debt using underlying token at a 1:1 exchange rate, without trading in a pool.
    /// It can add or remove collateral at the same time.
    /// The debt to repay is denominated in fyToken, even if the tokens pulled from the user are underlying.
    /// The debt to repay must be entered as a negative number, as with `pour`.
    /// Debt cannot be acquired with this function.
    function close(bytes12 vaultId, address to, int128 ink, int128 art)
        external payable
        returns (DataTypes.Balances memory balances_)
    {
        require (art < 0, "Only repay debt");                                          // When repaying debt in `frob`, art is a negative value. Here is the same for consistency.
        
        // Verify vault ownership
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");

        // Calculate debt in fyToken terms
        DataTypes.Series memory series_ = cauldron.series(vault_.seriesId);             // 1 CALL + 1 SLOAD
        bytes6 baseId = series_.baseId;
        uint128 amt;
        if (uint32(block.timestamp) >= series_.maturity) {
            IOracle rateOracle = cauldron.rateOracles(baseId);                          // 1 CALL + 1 SLOAD
            amt = uint128(-art).rmul(rateOracle.accrual(series_.maturity));             // Cost of `accrual`
        } else {
            amt = uint128(-art);
        }

        // Update accounting
        balances_ = cauldron.pour(vaultId, ink, art);                                       // Cost of `pour`

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin_ = joins[vault_.ilkId];
            require (ilkJoin_ != IJoin(address(0)), "Ilk join not found");
            if (ink > 0) ilkJoin_.join(vault_.owner, ink);
            if (ink < 0) ilkJoin_.join(to, ink);
        }

        // Manage underlying
        IJoin baseJoin_ = joins[series_.baseId];
        require (baseJoin_ != IJoin(address(0)), "Base join not found");
        baseJoin_.join(msg.sender, int128(amt));
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push base of borrowed series to user.
    /// The base is obtained by borrowing fyToken and selling it in a pool.
    function serve(bytes12 vaultId, address to, int128 ink, int128 art, uint128 min)
        external payable
        returns (DataTypes.Balances memory balances_, uint128 base_)
    {
        require (art > 0, "Only borrow");                                               // When borrowing with `frob`, art is a positive value.

        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        IPool pool_ = pools[vault_.seriesId];
        balances_ = pour(vaultId, address(pool_), ink, art);                            // Checks msg.sender owns the vault.
        base_ = pool_.sellFYToken(to);
        require (base_ >= min, "Slippage exceeded");
    }

    /// @dev Change series and debt of a vault.
    function roll(bytes12 vaultId, bytes6 seriesId, int128 art)
        public payable
        returns (uint128)
    {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        require (vault_.owner == msg.sender, "Only vault owner");
        // TODO: Buy underlying in the pool for the new series, and sell it in pool for the old series.
        // The new debt will be the amount of new series fyToken sold. This fyToken will be minted into the new series pool.
        // The amount obtained when selling the underlying must produce the exact amount to repay the existing debt. The old series fyToken amount will be burnt.
        
        return cauldron.roll(vaultId, seriesId, art);                              // Cost of `roll`
    }

    /// @dev Allow authorized contracts to move assets through the ladle
    // TODO: Come up with a different name, without underscore
    function _join(bytes12 vaultId, address user, int128 ink, int128 art)
        external
        auth
    {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);                       // 1 CALL + 1 SLOAD
        DataTypes.Series memory series_ = cauldron.series(vault_.seriesId);             // 1 CALL + 1 SLOAD

        if (ink != 0) {
            IJoin ilkJoin_ = joins[vault_.ilkId];
            require (ilkJoin_ != IJoin(address(0)), "Ilk join not found");
            ilkJoin_.join(user, ink);
        }
        if (art != 0) {
            IJoin baseJoin_ = joins[series_.baseId];
            require (baseJoin_ != IJoin(address(0)), "Base join not found");
            baseJoin_.join(user, art);
        }
    }

    // ---- Ether management ----

    IWETH9 public weth;

    /// @dev The WETH9 contract will send ether to BorrowProxy on `weth.withdraw` using this function.
    receive() external payable { }

    /// @dev Set the weth9 contract
    function setWeth(IWETH9 weth_) public auth {
        weth = weth_;
    }

    /// @dev Accept Ether, wrap it and forward it to the WethJoin
    /// This function should be called first in a multicall, and the Join should keep track of stored reserves
    function joinEther(bytes6 etherId)
        public payable
        returns (uint256 ethTransferred)
    {
        ethTransferred = address(this).balance;

        IJoin wethJoin = joins[etherId];
        require (address(wethJoin.token()) == address(weth), "Not a weth join");

        weth.deposit{ value: ethTransferred }();   // TODO: Test gas savings using WETH10 `depositTo`
        weth.transfer(address(wethJoin), ethTransferred);
    }

    /// @dev Unwrap Wrapped Ether held by this Ladle, and send the Ether
    /// This function should be called last in a multicall, and the Ladle should have no reason to keep an WETH balance
    function exitEther(address payable to)
        public payable
        returns (uint256 ethTransferred)
    {
        ethTransferred = weth.balanceOf(address(this));
        weth.withdraw(ethTransferred);   // TODO: Test gas savings using WETH10 `withdrawTo`
        to.transfer(ethTransferred); /// TODO: Consider reentrancy and safe transfers
    }
}