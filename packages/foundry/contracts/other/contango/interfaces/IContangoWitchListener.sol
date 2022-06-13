// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IContangoWitchListener {
    function auctionStarted(bytes12 vaultId) external;

    function collateralBought(
        bytes12 vaultId,
        address buyer,
        uint256 ink,
        uint256 art
    ) external;

    function auctionEnded(bytes12 vaultId, address owner) external;
}
