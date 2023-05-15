// SPDX-License-Identifier: BUSL-1.1
// Audited as of 15 May 2023. 
// Reports:
// https://github.com/yieldprotocol/variable-rate-audit-gogoauditor/issues/1
// https://github.com/yieldprotocol/variable-rate-audit-parth-15/issues?q=is%3Aissue+is%3Aclosed
// https://github.com/yieldprotocol/variable-rate-audit-obheda12/issues
// https://github.com/yieldprotocol/variable-rate-audit-DecorativePineapple/issues/19
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/src/utils/RevertMsgExtractor.sol";
import "@yield-protocol/utils-v2/src/utils/IsContract.sol";


/// @dev Router forwards calls between two contracts, so that any permissions
/// given to the original caller are stripped from the call.
/// This is useful when implementing generic call routing functions on contracts
/// that might have ERC20 approvals or AccessControl authorizations.
contract VRRouter {
    using IsContract for address;

    address public owner;

    /// @dev Set the owner, which is the only address that can route calls
    function initialize(address owner_) public {
        require(owner == address(0), "Already set");
        owner = owner_;
    }

    /// @dev Allow users to route calls, to be used with batch
    function route(address target, bytes calldata data)
        external payable
        returns (bytes memory result)
    {
        require(msg.sender == owner, "Only owner");
        require(target.isContract(), "Target is not a contract");
        bool success;
        (success, result) = target.call(data);
        if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
    }
}