// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.1;
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";


/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract LadleStorage {
    event JoinAdded(bytes6 indexed assetId, address indexed join);
    event PoolAdded(bytes6 indexed seriesId, address indexed pool);
    event ModuleSet(address indexed module, bool indexed set);
    event FeeSet(uint256 fee);

    IWETH9 public immutable weth;
    ICauldron public immutable cauldron;
    uint256 public borrowingFee;
    bytes12 cachedVaultId;

    mapping (bytes6 => IJoin)                   public joins;            // Join contracts available to manage assets. The same Join can serve multiple assets (ETH-A, ETH-B, etc...)
    mapping (bytes6 => IPool)                   public pools;            // Pool contracts available to manage series. 12 bytes still free.
    mapping (address => bool)                   public modules;          // Trusted contracts to execute anything on.

    constructor (ICauldron cauldron_, IWETH9 weth_) {
        cauldron = cauldron_;
        weth = weth_;
    }
}