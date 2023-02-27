// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../Router.sol";
import "./IJoin.sol";
import "./ICauldron.sol";
import "./IFYToken.sol";
import "./IOracle.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";

interface ILadle {

    // ---- Storage ----

    function cauldron() 
        external view
         returns(ICauldron);
    
    function router() 
        external view
         returns(Router);
    
    function weth() 
        external view
         returns(IWETH9);
    
    function borrowingFee() 
        external view
         returns(uint256);

    function joins(bytes6) 
        external view 
        returns (IJoin);

    function pools(bytes6) 
        external view 
        returns (address);

    function modules(address) 
        external view 
        returns (bool);

    function integrations(address) 
        external view 
        returns (bool);

    function tokens(address) 
        external view 
        returns (bool);
    
    // ---- Administration ----

    /// @dev Add or remove an integration.
    function addIntegration(address integration, bool set)
        external;

    /// @dev Add or remove a token that the Ladle can call `transfer` or `permit` on.
    function addToken(address token, bool set)
        external;


    /// @dev Add a new Join for an Asset, or replace an existing one for a new one.
    /// There can be only one Join per Asset. Until a Join is added, no tokens of that Asset can be posted or withdrawn.
    function addJoin(bytes6 assetId, IJoin join)
        external;

    /// @dev Add a new Pool for a Series, or replace an existing one for a new one.
    /// There can be only one Pool per Series. Until a Pool is added, it is not possible to borrow Base.
    function addPool(bytes6 seriesId, IPool pool)
        external;

    /// @dev Add or remove a module.
    /// @notice Treat modules as you would Ladle upgrades. Modules have unrestricted access to the Ladle
    /// storage, and can wreak havoc easily.
    /// Modules must not do any changes to any vault (owner, seriesId, ilkId) because of vault caching.
    /// Modules must not be contracts that can self-destruct because of `moduleCall`.
    /// Modules can't use `msg.value` because of `batch`.
    function addModule(address module, bool set)
        external;

    /// @dev Set the fee parameter
    function setFee(uint256 fee)
        external;

    // ---- Call management ----

    /// @dev Allows batched call to self (this contract).
    /// @param calls An array of inputs for each call.
    function batch(bytes[] calldata calls)
        external payable
        returns(bytes[] memory results);

    /// @dev Allow users to route calls to a contract, to be used with batch
    function route(address integration, bytes calldata data)
        external payable
        returns (bytes memory result);

    /// @dev Allow users to use functionality coded in a module, to be used with batch
    function moduleCall(address module, bytes calldata data)
        external payable
        returns (bytes memory result);

    // ---- Token management ----

    /// @dev Execute an ERC2612 permit for the selected token
    function forwardPermit(IERC2612 token, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external payable;

    /// @dev Execute a Dai-style permit for the selected token
    function forwardDaiPermit(IERC20 token, address spender, uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s)
        external payable;

    /// @dev Allow users to trigger a token transfer from themselves to a receiver through the ladle, to be used with batch
    function transfer(IERC20 token, address receiver, uint128 wad)
        external payable;

    /// @dev Retrieve any token in the Ladle
    function retrieve(IERC20 token, address to) 
        external payable
        returns (uint256 amount);

    /// @dev Accept Ether, wrap it and forward it to the WethJoin
    /// This function should be called first in a batch, and the Join should keep track of stored reserves
    /// Passing the id for a join that doesn't link to a contract implemnting IWETH9 will fail
    function joinEther(bytes6 etherId)
        external payable
        returns (uint256 ethTransferred);

    /// @dev Unwrap Wrapped Ether held by this Ladle, and send the Ether
    /// This function should be called last in a batch, and the Ladle should have no reason to keep an WETH balance
    function exitEther(address to)
        external payable
        returns (uint256 ethTransferred);

    // ---- Vault management ----

    /// @dev Create a new vault, linked to a series (and therefore underlying) and a collateral
    function build(bytes6 seriesId, bytes6 ilkId, uint8 salt)
        external payable
        returns(bytes12, DataTypes.Vault memory);

    /// @dev Change a vault series or collateral.
    function tweak(bytes12 vaultId_, bytes6 seriesId, bytes6 ilkId)
        external payable
        returns(DataTypes.Vault memory vault);

    /// @dev Give a vault to another user.
    function give(bytes12 vaultId_, address receiver)
        external payable
        returns(DataTypes.Vault memory vault);

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId_)
        external payable;

    // ---- Asset and debt management ----

    /// @dev Move collateral and debt between vaults.
    function stir(bytes12 from, bytes12 to, uint128 ink, uint128 art)
        external payable;

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    /// Borrow only before maturity.
    function pour(bytes12 vaultId_, address to, int128 ink, int128 art)
        external payable;

    /// @dev Add collateral and borrow from vault, so that a precise amount of base is obtained by the user.
    /// The base is obtained by borrowing fyToken and buying base with it in a pool.
    /// Only before maturity.
    function serve(bytes12 vaultId_, address to, uint128 ink, uint128 base, uint128 max)
        external payable
        returns (uint128 art);

    /// @dev Repay vault debt using underlying token at a 1:1 exchange rate, without trading in a pool.
    /// It can add or remove collateral at the same time.
    /// The debt to repay is denominated in fyToken, even if the tokens pulled from the user are underlying.
    /// The debt to repay must be entered as a negative number, as with `pour`.
    /// Debt cannot be acquired with this function.
    function close(bytes12 vaultId_, address to, int128 ink, int128 art)
        external payable
        returns (uint128 base);

    /// @dev Repay debt by selling base in a pool and using the resulting fyToken
    /// The base tokens need to be already in the pool, unaccounted for.
    /// Only before maturity. After maturity use close.
    function repay(bytes12 vaultId_, address to, int128 ink, uint128 min)
        external payable
        returns (uint128 art);

    /// @dev Repay all debt in a vault by buying fyToken from a pool with base.
    /// The base tokens need to be already in the pool, unaccounted for. The surplus base will be returned to msg.sender.
    /// Only before maturity. After maturity use close.
    function repayVault(bytes12 vaultId_, address to, int128 ink, uint128 max)
        external payable
        returns (uint128 base);

    /// @dev Change series and debt of a vault.
    function roll(bytes12 vaultId_, bytes6 newSeriesId, uint8 loan, uint128 max)
        external payable
        returns (DataTypes.Vault memory vault, uint128 newDebt);

    // ---- Ladle as a token holder ----

    /// @dev Use fyToken in the Ladle to repay debt. Return unused fyToken to `to`.
    /// Return as much collateral as debt was repaid, as well. This function is only used when
    /// removing liquidity added with "Borrow and Pool", so it's safe to assume the exchange rate
    /// is 1:1. If used in other contexts, it might revert, which is fine.
    function repayFromLadle(bytes12 vaultId_, address to)
        external payable
        returns (uint256 repaid);

    /// @dev Use base in the Ladle to repay debt. Return unused base to `to`.
    /// Return as much collateral as debt was repaid, as well. This function is only used when
    /// removing liquidity added with "Borrow and Pool", so it's safe to assume the exchange rate
    /// is 1:1. If used in other contexts, it might revert, which is fine.
    function closeFromLadle(bytes12 vaultId_, address to)
        external payable
        returns (uint256 repaid);

    /// @dev Allow users to redeem fyToken, to be used with batch.
    /// If 0 is passed as the amount to redeem, it redeems the fyToken balance of the Ladle instead.
    function redeem(bytes6 seriesId, address to, uint256 wad)
        external payable
        returns (uint256);
}
