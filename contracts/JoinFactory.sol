// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.8.0;

import "@yield-protocol/vault-interfaces/IJoinFactory.sol";
import "./Join.sol";


/// @dev The JoinFactory can deterministically create new join instances.
contract JoinFactory is IJoinFactory {

  /// @dev Deploys a new join.
  /// The asset address is written to a temporary storage slot to allow for simpler
  /// address calculation, while still allowing the Join contract to store the values as
  /// immutable.
  /// @param asset Address of the asset token.
  /// @return join The join address.
  function createJoin(address asset) external override returns (address) {
    Join join = new Join(asset);

    join.grantRole(join.ROOT(), msg.sender);
    join.renounceRole(join.ROOT(), address(this));
    
    emit JoinCreated(asset, address(join));

    return address(join);
  }
}