// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./IUSDT.sol";
import "../../interfaces/IJoin.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";

contract TetherJoin is IJoin, AccessControl {
    using TransferHelper for IERC20;

    address public immutable override asset;
    uint256 public override storedBalance;

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
            if (available == 0) {
                token.safeTransferFrom(user, address(this), amount);
                amount = uint128(token.balanceOf(address(this)) - _storedBalance);
            } else if (available < amount) {
                token.safeTransferFrom(user, address(this), (amount - available) * 1000000 / (1000000 - (IUSDT(asset).basisPointsRate() * 100)));
                amount = uint128(token.balanceOf(address(this)) - _storedBalance);
            }
            storedBalance = _storedBalance + amount; // Unlikely that a uint128 added to the stored balance will make it overflow
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
    function retrieve(IERC20 token, address to) external override auth {
        require(address(token) != address(asset), "Use exit for asset");
        token.safeTransfer(to, token.balanceOf(address(this)));
    }
}