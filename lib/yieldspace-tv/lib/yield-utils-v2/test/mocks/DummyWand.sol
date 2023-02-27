// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "src/utils/Pausable.sol";

contract DummyWand is Pausable {
  function actionWhenPaused() public whenPaused returns (uint256) {
    return 1;
  }

  function actionWhenNotPaused() public whenNotPaused returns (uint256) {
    return 2;
  }
}
