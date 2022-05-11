// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "../Witch.sol";
import "./interfaces/IContangoCauldron.sol";
import "./interfaces/IContangoWitchListener.sol";

contract ContangoWitch is Witch {

    IContangoWitchListener public immutable contango;
    constructor(IContangoWitchListener contango_, IContangoCauldron cauldron_, ILadle ladle_) Witch(cauldron_, ladle_) {
        contango = contango_;
    }
    
    function _auctionStarted(bytes12 vaultId) internal override {
        super._auctionStarted(vaultId);
        contango.auctionStarted(vaultId);
    }

    function _collateralBought(bytes12 vaultId, uint256 ink, uint256 art) internal override {
        super._collateralBought(vaultId, ink, art);
        contango.collateralBought(vaultId, ink, art);
    }

    function _auctionEnded(bytes12 vaultId, address owner) internal override {
        super._auctionEnded(vaultId, owner);
        contango.auctionEnded(vaultId, owner);
    }
}
