// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.1;
import "@yield-protocol/utils-v2/contracts/utils/RevertMsgExtractor.sol";

/// @dev Router forwards calls between two contracts, so that any permissions
/// given to the original caller are stripped from the call.
/// This is useful when implementing generic call routing functions on contracts
/// that might have ERC20 approvals or AccessControl authorizations.
contract Router {
    address immutable public owner;

    constructor () {
        owner = msg.sender;
    }

    /// @dev Allow users to route calls to a pool, to be used with batch
    function route(address target, bytes memory data)
        external payable
        returns (bytes memory result)
    {
        require(msg.sender == owner, "Only owner");
        bool success;
        (success, result) = target.call(data);
        if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
    }
}