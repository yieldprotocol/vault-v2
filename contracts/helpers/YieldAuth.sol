// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IERC2612.sol";
import "../interfaces/IDai.sol";
import "../interfaces/IDelegable.sol";


library YieldAuth {

    /// @dev Unpack r, s and v from a `bytes` signature
    function unpack(bytes memory signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
    }

    function addDelegate(IDelegable target, bytes memory signature) internal {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (signature.length > 0) {
            (r, s, v) = unpack(signature);
            target.addDelegateBySignature(msg.sender, address(this), type(uint256).max, v, r, s);
        }
    }

    function permitDai(IDai dai, address spender, bytes memory signature) internal {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (signature.length > 0) {
            (r, s, v) = unpack(signature);
            dai.permit(msg.sender, spender, dai.nonces(msg.sender), type(uint256).max, true, v, r, s);
        }
    }

    function permit(IERC2612 token, address spender, bytes memory signature) internal {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (signature.length > 0) {
            (r, s, v) = unpack(signature);
            token.permit(msg.sender, spender, type(uint256).max, type(uint256).max, v, r, s);
        }
    }
}