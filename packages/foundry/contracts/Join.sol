// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/IJoinFactory.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

contract Join is IJoin, AccessControl {
    using TransferHelper for IERC20;
    using WMul for uint256;
    using CastU256U128 for uint256;

    address public immutable override asset;
    uint256 public storedBalance;

    constructor(address asset_) {
        asset = asset_;
    }

    /// @dev Take `amount` `asset` from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    function join(address user, uint128 amount) external virtual override auth returns (uint128) {
        return _join(user, amount);
    }

    /// @dev Take `amount` `asset` from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    function _join(address user, uint128 amount) internal returns (uint128) {
        IERC20 token = IERC20(asset);
        uint256 _storedBalance = storedBalance;
        uint256 available = token.balanceOf(address(this)) - _storedBalance; // Fine to panic if this underflows
        unchecked {
            storedBalance = _storedBalance + amount; // Unlikely that a uint128 added to the stored balance will make it overflow
            if (available < amount) token.safeTransferFrom(user, address(this), amount - available);
        }
        return amount;
    }

    /// @dev Transfer `amount` `asset` to `user`
    function exit(address user, uint128 amount) external virtual override auth returns (uint128) {
        return _exit(user, amount);
    }

    /// @dev Transfer `amount` `asset` to `user`
    function _exit(address user, uint128 amount) internal returns (uint128) {
        IERC20 token = IERC20(asset);
        storedBalance -= amount;
        token.safeTransfer(user, amount);
        return amount;
    }

    /// @dev Retrieve any tokens other than the `asset`. Useful for airdropped tokens.
    function retrieve(IERC20 token, address to) external auth {
        require(address(token) != address(asset), "Use exit for asset");
        token.safeTransfer(to, token.balanceOf(address(this)));
    }
}
