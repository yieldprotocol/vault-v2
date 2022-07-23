// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/MinimalTransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./IBatchAction.sol";
import "./ERC1155.sol";


contract NotionalJoin is IJoin, ERC1155TokenReceiver, AccessControl() {
    using WMul for uint256;
    using WDiv for uint256;
    using CastU256U128 for uint256;

    event FlashFeeFactorSet(uint256 indexed fee);
    event Redeemed(uint256 fCash, uint256 underlying, uint256 accrual);

    bytes32 constant internal FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 constant public FLASH_LOANS_DISABLED = type(uint256).max;

    address public immutable override asset;
    address public immutable underlying;
    address public immutable underlyingJoin;
    uint40 public immutable maturity;    // Maturity date for fCash
    uint16 public immutable currencyId;  // Notional currency id for the underlying
    uint256 public immutable id;         // This ERC1155 Join only accepts one id from the ERC1155 token
    uint256 public storedBalance;        // After maturity, this is reused as the balance for underlying
    uint256 public accrual;              // fCash to underlying factor, with 18 decimals
    uint256 public flashFeeFactor = FLASH_LOANS_DISABLED; // Fee on flash loans, as a percentage in fixed point with 18 decimals. Flash loans disabled by default.

    constructor(address asset_, address underlying_, address underlyingJoin_, uint40 maturity_, uint16 currencyId_) {
        asset = asset_;
        underlying = underlying_;
        maturity = maturity_;
        currencyId = currencyId_;
        underlyingJoin = underlyingJoin_;

        // TransferAssets.encodeAssetId
        id = uint256(
            (bytes32(uint256(currencyId_)) << 48) |
            (bytes32(uint256(maturity_)) << 8) |
            bytes32(uint256(1))
        );
    }

    modifier afterMaturity() {
        require(block.timestamp >= maturity, "Only after maturity");
        _;
    }

    modifier beforeMaturity() {
        require(block.timestamp < maturity,"Only before maturity");
        _;
    }

    /// @dev Advertising through ERC165 the available functions
    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        // ERC-165 support = `bytes4(keccak256('supportsInterface(bytes4)'))`.
        // ERC-1155 `ERC1155TokenReceiver` support = `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`.
        return  interfaceID == NotionalJoin.supportsInterface.selector ||
                interfaceID == ERC1155TokenReceiver.onERC1155Received.selector ^ ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }

    /// @dev Called by the sender after a transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155Received(address, address, uint256 _id, uint256, bytes calldata) external override returns(bytes4) {
        require (_id == id, "Token id not accepted");
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @dev Called by the sender after a batch transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155BatchReceived(address, address, uint256[] calldata _ids, uint256[] calldata, bytes calldata) external override returns(bytes4) {
        uint256 length = _ids.length;
        for (uint256 i; i < length; ++i)
            require (_ids[i] == id, "Token id not accepted");
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }

    /// @dev Take `amount` `asset` from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    /// @param user Address of receiver of tokens
    /// @param amount Amount of tokens
    function join(address user, uint128 amount) external override auth returns (uint128) {
        return _join(user, amount);
    }

    /// @dev Take `amount` `asset` from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    /// @param user Address of receiver of tokens
    /// @param amount Amount of tokens
    function _join(address user, uint128 amount) internal beforeMaturity returns (uint128) {
        ERC1155 token = ERC1155(asset);
        uint256 _storedBalance = storedBalance;
        uint256 available = token.balanceOf(address(this), id) - _storedBalance; // Fine to panic if this underflows
        
        unchecked {
            storedBalance = _storedBalance + amount;    // Unlikely that a uint128 added to the stored balance will make it overflow
            if (available < amount) token.safeTransferFrom(user, address(this), id, amount - available, "");
        }
        return amount;        
    }

    /// @dev Before maturity, transfer `amount` `asset` to `user`.
    /// @param user Address of receiver of tokens
    /// @param amount Amount of tokens
    /// After maturity, withdraw if necessary, then transfer `amount.wmul(accrual)` `underlying` to `user`.
    function exit(address user, uint128 amount) external override auth returns (uint128) {
        if (block.timestamp < maturity) {
            return _exit(user, amount);
        } else {
            if (accrual == 0) redeem(); // Redeem all fCash, switch to underlying join, set accrual.
            return _exitUnderlying(user, uint256(amount).wmul(accrual).u128());
        }
    }

    /// @dev Transfer `amount` `asset` to `user`
    /// @param user Address of receiver of fCash tokens
    /// @param amount Amount of ERC1155 tokens
    function _exit(address user, uint128 amount) internal beforeMaturity returns (uint128) {
        storedBalance -= amount;
        ERC1155(asset).safeTransferFrom(address(this), user, id, amount, "");
        return amount;
    }

    /// @dev Transfer `amount` `underlying` to `user`
    /// @param user Recipient of token transfer
    /// @param amount Amount of underlying tokens to transfer
    function _exitUnderlying(address user, uint128 amount) internal afterMaturity returns (uint128) {
        IJoin(underlyingJoin).exit(user, amount);
        return amount;
    }

    /// @dev Converts all fCash holdings to underlying and send it to the main underlying join
    function redeem() public afterMaturity {
        require (accrual == 0, "Already redeemed");

        // Build an action to withdraw all mature fCash into underlying, then withdraw.
        IBatchAction.BalanceAction[] memory withdrawActions = new IBatchAction.BalanceAction[](1);
        withdrawActions[0] = IBatchAction.BalanceAction({
            actionType: IBatchAction.DepositActionType.None,
            currencyId: currencyId,
            depositActionAmount: 0,
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: true,
            redeemToUnderlying: true
        });

        IBatchAction(asset).batchBalanceAction(address(this), withdrawActions);

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        uint256 storedBalance_ = storedBalance;
        accrual = underlyingBalance.wdiv(storedBalance_); // There is a rounding loss here. Some wei will be forever locked in the join.
        
        // transfer underlying to main join
        MinimalTransferHelper.safeTransfer(IERC20(underlying), address(underlyingJoin), underlyingBalance);
        IJoin(underlyingJoin).join(address(this), underlyingBalance.u128());

        // no more fCash left in holding
        storedBalance = 0;

        emit Redeemed(storedBalance_, underlyingBalance, accrual);
    }

    /// @dev Retrieve any ERC20 tokens. Useful for airdropped tokens.
    /// @param token ERC20 contract object
    /// @param to Address of receiver
    function retrieve(IERC20 token, address to) external auth {
        require(address(token) != address(underlying), "Use exit for underlying");
        MinimalTransferHelper.safeTransfer(token, to, token.balanceOf(address(this)));
    }
    
    /// @dev Retrieve any ERC1155 tokens other than the `asset`. Useful for airdropped tokens.
    /// @param token ERC1155 token passed as contract object
    /// @param id_ ID of ERC1155 token
    /// @param to Address of receiver
    function retrieveERC1155(ERC1155 token, uint256 id_, address to) external auth {
        require(address(token) != address(asset) || id_ != id, "Use exit for asset");
        token.safeTransferFrom(address(this), to, id_, token.balanceOf(address(this), id_), "");
    }
}