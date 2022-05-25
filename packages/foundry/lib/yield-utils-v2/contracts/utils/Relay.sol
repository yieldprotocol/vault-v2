// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../access/Ownable.sol";
import "./RevertMsgExtractor.sol";
import "./IsContract.sol";

/// @dev Relay is a simple contract to batch several contract calls into one single transaction.
contract Relay is Ownable() {
    using IsContract for address;

    struct Call {
        address target;
        bytes data;
    }

    /// @dev Execute a series of function calls
    function execute(Call[] calldata functionCalls)
        external onlyOwner returns (bytes[] memory results)
    {
        results = new bytes[](functionCalls.length);
        for (uint256 i = 0; i < functionCalls.length; i++){
            require(functionCalls[i].target.isContract(), "Call to a non-contract");
            (bool success, bytes memory result) = functionCalls[i].target.call(functionCalls[i].data);
            if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
            results[i] = result;
        }
    }
}