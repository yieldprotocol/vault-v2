// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/MinimalTransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./ERC1155.sol"; // TODO: Move to yield-utils-v2
// ERC1155TokenReceiver is in ERC1155.sol

contract Join1155 is IJoin, ERC1155TokenReceiver, AccessControl() {
    using WMul for uint256;
    using CastU256U128 for uint256;

    event FlashFeeFactorSet(uint256 indexed fee);

    bytes32 constant internal FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 constant FLASH_LOANS_DISABLED = type(uint256).max;

    address public immutable override asset;
    uint256 public immutable id;    // This ERC1155 Join only accepts one id from the ERC1155 token
    uint256 public storedBalance;
    uint256 public flashFeeFactor = FLASH_LOANS_DISABLED; // Fee on flash loans, as a percentage in fixed point with 18 decimals. Flash loans disabled by default.

    constructor(address asset_, uint256 id_) {
        asset = asset_;
        id = id_;
    }

    /// @dev Advertising through ERC165 the available functions
    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        // ERC-165 support = `bytes4(keccak256('supportsInterface(bytes4)'))`.
        // ERC-1155 `ERC1155TokenReceiver` support = `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`.
        return  interfaceID == Join1155.supportsInterface.selector ||
                interfaceID == ERC1155TokenReceiver.onERC1155Received.selector ^ ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }

    /// @dev Called by the sender after a transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external override returns(bytes4) {
        require (_id == id, "Token id not accepted");
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @dev Called by the sender after a batch transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external override returns(bytes4) {
        uint256 length = _ids.length;
        for (uint256 i; i < length; ++i)
            require (_ids[i] == id, "Token id not accepted");
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }

    /// @dev Take `amount` `asset` from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    function join(address user, uint128 amount)
        external override
        auth
        returns (uint128)
    {
        return _join(user, amount);
    }

    /// @dev Take `amount` `asset` from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    function _join(address user, uint128 amount)
        internal
        returns (uint128)
    {
        ERC1155 token = ERC1155(asset);
        uint256 _storedBalance = storedBalance;
        uint256 available = token.balanceOf(address(this), id) - _storedBalance; // Fine to panic if this underflows
        storedBalance = _storedBalance + amount;
        unchecked { if (available < amount) token.safeTransferFrom(user, address(this), id, amount - available, ""); }
        return amount;        
    }

    /// @dev Transfer `amount` `asset` to `user`
    function exit(address user, uint128 amount)
        external override
        auth
        returns (uint128)
    {
        return _exit(user, amount);
    }

    /// @dev Transfer `amount` `asset` to `user`
    function _exit(address user, uint128 amount)
        internal
        returns (uint128)
    {
        ERC1155 token = ERC1155(asset);
        storedBalance -= amount;
        token.safeTransferFrom(address(this), user, id, amount, "");
        return amount;
    }

    /// @dev Retrieve any ERC1155 tokens other than the `asset`. Useful for airdropped tokens.
    function retrieve(ERC1155 token, uint256 id_, address to)
        external
        auth
    {
        require(address(token) != address(asset) || id_ != id, "Use exit for asset");
        token.safeTransferFrom(address(this), to, id_, token.balanceOf(address(this), id_), "");
    }

    /// @dev Retrieve any ERC20 tokens. Useful for airdropped tokens.
    function retrieveERC20(IERC20 token, address to)
        external
        auth
    {
        MinimalTransferHelper.safeTransfer(token, to, token.balanceOf(address(this)));
    }
}