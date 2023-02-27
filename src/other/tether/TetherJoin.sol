// SPDX-License-Identifier: BUSL-1.1
// Audit as of 2023-02-03, commit 99464fe, https://hackmd.io/AY6oeTvVSCyLdCh1MEG7yQ
pragma solidity >=0.8.13;

import "./IUSDT.sol";
import "../../FlashJoin.sol";
import "@yield-protocol/utils-v2/src/token/IERC20.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";

/// @dev Tether includes code in its contract to apply a fee to transfers. In developing this contract,
/// we took a selfish approach. The TetherJoin will only care about the amount that USDT that it receives,
/// and about the amount of USDT that it sends. If fees are enabled, the TetherJoin will expect to have 
/// the amount specified in the join function arguments, and if pulling from the user, it will pull the
/// amount that it expects to receive, plus the fee. Likewise, if sending to the user, it will send the
/// amount specified as an argument, and it is responsibility of the receiver to deal with any shortage
/// on receival due to fees. This aproach extends to flash loans.
contract TetherJoin is FlashJoin {
    using TransferHelper for IERC20;
    using Math for *;

    constructor(address asset_) FlashJoin(asset_) {}

    /// @dev Calculate the minimum of two uint256s.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Calculate the amount of `asset` that needs to be sent to receive `amount` of USDT.
    function _reverseFee(uint256 amount) internal view returns (uint256) {
        return _min(amount.wdiv(1e18 - IUSDT(asset).basisPointsRate() * 1e14), amount + IUSDT(asset).maximumFee());
    }

    /// @dev Take `asset` from `user` using `transferFrom`, minus any unaccounted `asset` in this contract, so that `amount` of USDT is received.
    function _join(address user, uint128 amount) internal override returns (uint128) {
        IERC20 token = IERC20(asset);
        uint256 _storedBalance = storedBalance;
        uint256 available = token.balanceOf(address(this)) - _storedBalance; // Fine to panic if this underflows
        unchecked {
            if (available == 0) {
                token.safeTransferFrom(user, address(this), _reverseFee(amount));
                amount = uint128(token.balanceOf(address(this)) - _storedBalance);
            } else if (available < amount) {
                token.safeTransferFrom(user, address(this), _reverseFee(amount - available));
                amount = uint128(token.balanceOf(address(this)) - _storedBalance);
            }
            storedBalance = _storedBalance + amount; // Unlikely that a uint128 added to the stored balance will make it overflow
        }
        return amount;
    }
}