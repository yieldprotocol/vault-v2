// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/vault-interfaces/IJoinFactory.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./Join.sol";


/// @dev The JoinFactory creates new join instances.
contract JoinFactory is IJoinFactory, AccessControl {

  /// @dev Deploys a new join.
  /// @param asset Address of the asset token.
  /// @return join The join address.
  function createJoin(address asset)
    external override
    auth
    returns (address)
  {
    Join join = new Join(asset);

    join.grantRole(ROOT, msg.sender);
    join.renounceRole(ROOT, address(this));
    
    emit JoinCreated(asset, address(join));

    return address(join);
  }
}