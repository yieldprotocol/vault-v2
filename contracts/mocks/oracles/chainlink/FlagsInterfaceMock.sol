// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import '../../../oracles/chainlink/FlagsInterface.sol';

/**
Mock FlagsInterface

We're not supposed to directly manipulate flags from our tests, so all methods raise
Use helper functions to manipulate flags at higher abstraction level
 */
contract FlagsInterfaceMock is FlagsInterface {
    // interface
    mapping(address => bool) flags;

    function getFlag(address f) external view override returns (bool) {
        return flags[f];
    }

    function getFlags(address[] calldata) external pure override returns (bool[] memory) {
        revert('not implemented');
    }

    function raiseFlag(address) external pure override {
        revert('not implemented');
    }

    function raiseFlags(address[] calldata) external pure override {
        revert('not implemented');
    }

    function lowerFlags(address[] calldata) external pure override {
        revert('not implemented');
    }

    function setRaisingAccessController(address) external pure override {
        revert('not implemented');
    }

    // helpers
    function flagSetArbitrumSeqOffline(bool value) public {
        address flag = address(bytes20(bytes32(uint256(keccak256('chainlink.flags.arbitrum-seq-offline')) - 1)));
        flags[flag] = value;
    }
}
