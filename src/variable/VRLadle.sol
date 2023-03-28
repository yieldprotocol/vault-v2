// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "../interfaces/IFYToken.sol";
import "../interfaces/IJoin.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/DataTypes.sol";
import "../interfaces/IRouter.sol";
import "./interfaces/IVRCauldron.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/src/token/IERC20.sol";
import "@yield-protocol/utils-v2/src/token/IERC2612.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "dss-interfaces/src/dss/DaiAbstract.sol";
import { UUPSUpgradeable } from "openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient user oriented features.
contract VRLadle is UUPSUpgradeable, AccessControl() {
    using Math for uint256;
    using Cast for uint256;
    using Cast for uint128;
    using TransferHelper for IERC20;
    using TransferHelper for address payable;

    event JoinAdded(bytes6 indexed assetId, address indexed join);
    event IntegrationAdded(address indexed integration, bool indexed set);
    event TokenAdded(address indexed token, bool indexed set);
    event FeeSet(uint256 fee);

    bool public initialized;
    IVRCauldron public immutable cauldron;
    IRouter public immutable router;
    IWETH9 public immutable weth;
    uint256 public borrowingFee;
    bytes12 cachedVaultId;

    mapping (bytes6 => IJoin)                   public joins;            // Join contracts available to manage assets. The same Join can serve multiple assets (ETH-A, ETH-B, etc...)
    mapping (address => bool)                   public integrations;     // Trusted contracts to call anything on.
    mapping (address => bool)                   public tokens;           // Trusted contracts to call `transfer` or `permit` on.

    constructor (IVRCauldron cauldron_, IRouter router_, IWETH9 weth_) {
        cauldron = cauldron_;
        router = router_;
        weth = weth_;

        // See https://medium.com/immunefi/wormhole-uninitialized-proxy-bugfix-review-90250c41a43a
        initialized = true; // Lock the implementation contract
    }

    // ---- Upgradability ----

    /// @dev Give the ROOT role and create a LOCK role with itself as the admin role and no members. 
    /// Calling setRoleAdmin(msg.sig, LOCK) means no one can grant that msg.sig role anymore.
    function initialize (address root_) public {
        require(!initialized, "Already initialized");
        initialized = true;             // On an uninitialized contract, no governance functions can be executed, because no one has permission to do so
        _grantRole(ROOT, root_);   // Grant ROOT
        _setRoleAdmin(LOCK, LOCK);      // Create the LOCK role by setting itself as its own admin, creating an independent role tree
    }

    /// @dev Allow to set a new implementation
    function _authorizeUpgrade(address newImplementation) internal override auth {}

    // ---- Data sourcing ----
    /// @dev Obtains a vault by vaultId from the Cauldron, and verifies that msg.sender is the owner
    /// If bytes(0) is passed as the vaultId it tries to load a vault from the cache
    function getVault(
        bytes12 vaultId_
    ) internal view returns (bytes12 vaultId, VRDataTypes.Vault memory vault) {
        if (vaultId_ == bytes12(0)) {
            // We use the cache
            require(cachedVaultId != bytes12(0), "Vault not cached");
            vaultId = cachedVaultId;
        } else {
            vaultId = vaultId_;
        }
        vault = cauldron.vaults(vaultId);
        require(vault.owner == msg.sender, "Only vault owner");
    }

    /// @dev Obtains a join by assetId, and verifies that it exists
    function getJoin(bytes6 assetId) internal view returns (IJoin join) {
        join = joins[assetId];
        require(join != IJoin(address(0)), "Join not found");
    }

    // ---- Administration ----

    /// @dev Add or remove an integration.
    function addIntegration(address integration, bool set) external auth {
        _addIntegration(integration, set);
    }

    /// @dev Add or remove an integration.
    function _addIntegration(address integration, bool set) private {
        integrations[integration] = set;
        emit IntegrationAdded(integration, set);
    }

    /// @dev Add or remove a token that the Ladle can call `transfer` or `permit` on.
    function addToken(address token, bool set) external auth {
        _addToken(token, set);
    }

    /// @dev Add or remove a token that the Ladle can call `transfer` or `permit` on.
    function _addToken(address token, bool set) private {
        tokens[token] = set;
        emit TokenAdded(token, set);
    }

    /// @dev Add a new Join for an Asset, or replace an existing one for a new one.
    /// There can be only one Join per Asset. Until a Join is added, no tokens of that Asset can be posted or withdrawn.
    function addJoin(bytes6 assetId, IJoin join) external auth {
        address asset = cauldron.assets(assetId);
        require(asset != address(0), "Asset not found");
        require(join.asset() == asset, "Mismatched asset and join");
        joins[assetId] = join;

        bool set = (join != IJoin(address(0))) ? true : false;
        _addToken(asset, set); // address(0) disables the token
        emit JoinAdded(assetId, address(join));
    }

    /// @dev Set the fee parameter
    function setFee(uint256 fee) external auth {
        borrowingFee = fee;
        emit FeeSet(fee);
    }

    // ---- Call management ----

    /// @dev Allows batched call to self (this contract).
    /// @param calls An array of inputs for each call.
    function batch(
        bytes[] calldata calls
    ) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(
                calls[i]
            );
            if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
            results[i] = result;
        }

        // build would have populated the cache, this deletes it
        cachedVaultId = bytes12(0);
    }

    /// @dev Allow users to route calls to a contract, to be used with batch
    function route(
        address integration,
        bytes calldata data
    ) external payable returns (bytes memory result) {
        require(integrations[integration], "Unknown integration");
        return router.route(integration, data);
    }

    // ---- Token management ----

    /// @dev Execute an ERC2612 permit for the selected token
    function forwardPermit(
        IERC2612 token,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        require(tokens[address(token)], "Unknown token");
        token.permit(msg.sender, spender, amount, deadline, v, r, s);
    }

    /// @dev Execute a Dai-style permit for the selected token
    function forwardDaiPermit(
        DaiAbstract token,
        address spender,
        uint256 nonce,
        uint256 deadline,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        require(tokens[address(token)], "Unknown token");
        token.permit(msg.sender, spender, nonce, deadline, allowed, v, r, s);
    }

    /// @dev Allow users to trigger a token transfer from themselves to a receiver through the ladle, to be used with batch
    function transfer(
        IERC20 token,
        address receiver,
        uint128 wad
    ) external payable {
        require(tokens[address(token)], "Unknown token");
        token.safeTransferFrom(msg.sender, receiver, wad);
    }

    /// @dev Retrieve any token in the Ladle
    function retrieve(
        IERC20 token,
        address to
    ) external payable returns (uint256 amount) {
        require(tokens[address(token)], "Unknown token");
        amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);
    }

    /// @dev The WETH9 contract will send ether to BorrowProxy on `weth.withdraw` using this function.
    receive() external payable {
        require(msg.sender == address(weth), "Only receive from WETH");
    }

    /// @dev Accept Ether, wrap it and forward it to the provided address
    /// This function should be called first in a batch, and the Join should keep track of stored reserves
    /// Passing the id for a join that doesn't link to a contract implemnting IWETH9 will fail
    function wrapEther(
        address to
    ) external payable returns (uint256 ethTransferred) {
        ethTransferred = address(this).balance;
        weth.deposit{value: ethTransferred}();
        IERC20(address(weth)).safeTransfer(to, ethTransferred);
    }

    /// @dev Unwrap Wrapped Ether held by this Ladle, and send the Ether
    /// This function should be called last in a batch, and the Ladle should have no reason to keep an WETH balance
    function unwrapEther(
        address payable to
    ) external payable returns (uint256 ethTransferred) {
        ethTransferred = weth.balanceOf(address(this));
        weth.withdraw(ethTransferred);
        to.safeTransferETH(ethTransferred);
    }

    // ---- Vault management ----

    /// @dev Generate a vaultId. A keccak256 is cheaper than using a counter with a SSTORE, even accounting for eventual collision retries.
    function _generateVaultId(uint8 salt) private view returns (bytes12) {
        return
            bytes12(
                keccak256(abi.encodePacked(msg.sender, block.timestamp, salt))
            );
    }

    /// @dev Create a new vault, linked to a base and a collateral
    function build(
        bytes6 baseId,
        bytes6 ilkId,
        uint8 salt
    ) external payable virtual returns (bytes12, VRDataTypes.Vault memory) {
        return _build(baseId, ilkId, salt);
    }

    /// @dev Create a new vault, linked to a base and a collateral
    function _build(
        bytes6 baseId,
        bytes6 ilkId,
        uint8 salt
    ) internal returns (bytes12 vaultId, VRDataTypes.Vault memory vault) {
        vaultId = _generateVaultId(salt);
        while (cauldron.vaults(vaultId).baseId != bytes6(0))
            vaultId = _generateVaultId(++salt); // If the vault exists, generate other random vaultId
        vault = cauldron.build(msg.sender, vaultId, baseId, ilkId);
        // Store the vault data in the cache
        cachedVaultId = vaultId;
    }

    /// @dev Change a vault base or collateral.
    function tweak(
        bytes12 vaultId_,
        bytes6 baseId,
        bytes6 ilkId
    ) external payable returns (VRDataTypes.Vault memory vault) {
        (bytes12 vaultId, ) = getVault(vaultId_); // getVault verifies the ownership as well
        // tweak checks that the base and the collateral both exist and that the collateral is approved for the base
        vault = cauldron.tweak(vaultId, baseId, ilkId);
    }

    /// @dev Give a vault to another user.
    function give(
        bytes12 vaultId_,
        address receiver
    ) external payable returns (VRDataTypes.Vault memory vault) {
        (bytes12 vaultId, ) = getVault(vaultId_);
        vault = cauldron.give(vaultId, receiver);
    }

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vaultId_) external payable {
        (bytes12 vaultId, ) = getVault(vaultId_);
        cauldron.destroy(vaultId);
    }

    // ---- Asset and debt management ----

    /// @dev Move collateral and debt between vaults.
    function stir(
        bytes12 from,
        bytes12 to,
        uint128 ink,
        uint128 art
    ) external payable {
        if (ink > 0)
            require(
                cauldron.vaults(from).owner == msg.sender,
                "Only origin vault owner"
            );
        if (art > 0)
            require(
                cauldron.vaults(to).owner == msg.sender,
                "Only destination vault owner"
            );
        cauldron.stir(from, to, ink, art);
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    /// Borrow only before maturity.
    function _pour(
        bytes12 vaultId,
        VRDataTypes.Vault memory vault,
        address to,
        int128 ink,
        int128 base
    ) private {
        int128 fee;
        if (base > 0 && vault.ilkId != vault.baseId && borrowingFee != 0)
            fee = uint256(int256(base)).wmul(borrowingFee).i128();

        // Update accounting
        cauldron.pour(vaultId, ink, base + fee);

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            if (ink > 0) ilkJoin.join(vault.owner, uint128(ink));
            if (ink < 0) ilkJoin.exit(to, uint128(-ink));
        }

        // Manage base
        if (base != 0) {
            IJoin baseJoin = getJoin(vault.baseId);
            if (base < 0) baseJoin.join(vault.owner, uint128(-base));
            if (base > 0) baseJoin.exit(to, uint128(base));
        }
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    /// Borrow only before maturity.
    function pour(
        bytes12 vaultId_,
        address to,
        int128 ink,
        int128 base
    ) external payable {
        (bytes12 vaultId, VRDataTypes.Vault memory vault) = getVault(vaultId_);
        _pour(vaultId, vault, to, ink, base);
    }

    /// @dev Repay all debt in a vault.
    /// The base tokens need to be already in the join, unaccounted for. The surplus base will be returned to msg.sender.
    function repay(
        bytes12 vaultId_,
        address inkTo,
        address refundTo,
        int128 ink
    ) external payable returns (uint128 base, uint256 refund) {
        (bytes12 vaultId, VRDataTypes.Vault memory vault) = getVault(vaultId_);

        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        base = cauldron.debtToBase(vault.baseId, balances.art);
        _pour(vaultId, vault, inkTo, ink, -(base.i128()));

        // Given the low rate of change, we probably prefer to send a few extra wei to the join,
        // ask for no refund (with refundTo == address(0)), and save gas
        if (refundTo != address(0)) {
            IJoin baseJoin = getJoin(vault.baseId);
            refund =
                IERC20(baseJoin.asset()).balanceOf(address(baseJoin)) -
                baseJoin.storedBalance();
            baseJoin.exit(refundTo, refund.u128());
        }
    }
}
