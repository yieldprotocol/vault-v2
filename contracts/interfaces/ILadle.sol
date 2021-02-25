// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;


interface ILadle {
    /// @dev Allow authorized contracts to move assets through the ladle
    function _join(bytes12 vaultId, address user, int128 ink, int128 art) external;
}