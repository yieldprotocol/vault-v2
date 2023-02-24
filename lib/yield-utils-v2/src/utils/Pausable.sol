// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../access/AccessControl.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */

contract Pausable is AccessControl {

  error RequirePaused(address msgSender, bool pausedState);
  error RequireUnpaused(address msgSender, bool pausedState);    

  /// @dev Emitted when contract's pause state is modified
  event Paused(address indexed account, bool indexed state);

  bool public paused;

  /// @dev Initializes the contract in unpaused state.
  constructor() {
    paused = false;
  }

  /// @dev Triggers paused state. Requires: contract must not be paused
  function pause() external auth whenNotPaused {
    paused = true;
    emit Paused(msg.sender, paused);
  }

  /// @dev Returns to active state. Requires: contract must be paused
  function unpause() external auth whenPaused {
    paused = false;
    emit Paused(msg.sender, paused);
  }

  /// @dev Modifier to make a function callable only when the contract is not paused
  modifier whenNotPaused() {
    if(paused != false){
      revert RequirePaused({msgSender: msg.sender, pausedState: paused});
    }
    //require(paused == false, "Pausable: paused");
    _;
  }

  modifier whenPaused() {
    //require(paused == true, "Pausable: not paused");
    if(paused != true){
      revert RequireUnpaused({msgSender: msg.sender, pausedState: paused});
    }
    _;
  }
}
