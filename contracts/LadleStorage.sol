// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "./Router.sol";


/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract LadleStorage {
    event JoinAdded(bytes6 indexed assetId, address indexed join);
    event PoolAdded(bytes6 indexed seriesId, address indexed pool);
    event ModuleAdded(address indexed module, bool indexed set);
    event IntegrationAdded(address indexed integration, bool indexed set);
    event TokenAdded(address indexed token, bool indexed set);
    event FeeSet(uint256 fee);

    ICauldron public immutable cauldron;
    Router public immutable router;
    IWETH9 public immutable weth;
    uint256 public borrowingFee;
    bytes12 cachedVaultId;

    mapping (bytes6 => IJoin)                   public joins;            // Join contracts available to manage assets. The same Join can serve multiple assets (ETH-A, ETH-B, etc...)
    mapping (bytes6 => IPool)                   public pools;            // Pool contracts available to manage series. 12 bytes still free.
    mapping (address => bool)                   public modules;          // Trusted contracts to delegatecall anything on.
    mapping (address => bool)                   public integrations;     // Trusted contracts to call anything on.
    mapping (address => bool)                   public tokens;           // Trusted contracts to call `transfer` or `permit` on.

    constructor (ICauldron cauldron_, IWETH9 weth_) {
        cauldron = cauldron_;
        router = new Router();
        weth = weth_;
    }
}