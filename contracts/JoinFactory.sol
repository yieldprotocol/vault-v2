// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.8.0;

import "@yield-protocol/vault-interfaces/IJoinFactory.sol";
import "./Join.sol";


/// @dev The JoinFactory can deterministically create new join instances.
contract JoinFactory is IJoinFactory {

  address private _nextAsset;

  /// @dev Deploys a new join.
  /// The asset address is written to a temporary storage slot to allow for simpler
  /// address calculation, while still allowing the Join contract to store the values as
  /// immutable.
  /// @param asset Address of the asset token.
  /// @return join The join address.
  function createJoin(address asset) external override returns (address) {
    _nextAsset = asset;
    Join join = new Join();
    _nextAsset = address(0);

    join.grantRole(join.ROOT(), msg.sender);
    join.renounceRole(join.ROOT(), address(this));
    
    emit JoinCreated(asset, address(join));

    return address(join);
  }

  /// @dev Only used by the Join constructor.
  /// @return The address token for the currently-constructing join.
  function nextAsset() external view override returns (address) {
    return _nextAsset;
  }
}