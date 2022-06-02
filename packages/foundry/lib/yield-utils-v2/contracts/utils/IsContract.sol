// SPDX-License-Identifier: MIT
// Taken from Address.sol from OpenZeppelin.
pragma solidity ^0.8.0;


library IsContract {
  /// @dev Returns true if `account` is a contract.
  function isContract(address account) internal view returns (bool) {
      // This method relies on extcodesize, which returns 0 for contracts in
      // construction, since the code is only stored at the end of the
      // constructor execution.
      return account.code.length > 0;
  }
}
