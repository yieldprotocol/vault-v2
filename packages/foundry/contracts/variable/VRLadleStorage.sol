// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "../Router.sol";
import "../interfaces/IJoin.sol";
import "./interfaces/IVRCauldron.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";


/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract VRLadleStorage {
    event JoinAdded(bytes6 indexed assetId, address indexed join);
    event ModuleAdded(address indexed module, bool indexed set);
    event IntegrationAdded(address indexed integration, bool indexed set);
    event TokenAdded(address indexed token, bool indexed set);
    event FeeSet(uint256 fee);

    IVRCauldron public immutable cauldron;
    Router public immutable router;
    IWETH9 public immutable weth;
    uint256 public borrowingFee;
    bytes12 cachedVaultId;

    mapping (bytes6 => IJoin)                   public joins;            // Join contracts available to manage assets. The same Join can serve multiple assets (ETH-A, ETH-B, etc...)
    mapping (address => bool)                   public modules;          // Trusted contracts to delegatecall anything on.
    mapping (address => bool)                   public integrations;     // Trusted contracts to call anything on.
    mapping (address => bool)                   public tokens;           // Trusted contracts to call `transfer` or `permit` on.

    constructor (IVRCauldron cauldron_, IWETH9 weth_) {
        cauldron = cauldron_;
        router = new Router();
        weth = weth_;
    }
}