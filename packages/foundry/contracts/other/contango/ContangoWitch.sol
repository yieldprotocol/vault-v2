// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../Witch.sol";
import "./interfaces/IContangoWitchListener.sol";

contract ContangoWitch is Witch {
    IContangoWitchListener public immutable contango;

    constructor(
        IContangoWitchListener contango_,
        ICauldron cauldron_,
        ILadle ladle_
    ) Witch(cauldron_, ladle_) {
        contango = contango_;
    }

    function _auctionStarted(
        bytes12 vaultId,
        DataTypes.Auction memory auction_,
        DataTypes.Line memory line
    ) internal override returns (DataTypes.Vault memory vault) {
        vault = super._auctionStarted(vaultId, auction_, line);
        contango.auctionStarted(vaultId);
    }

    function _collateralBought(
        bytes12 vaultId,
        address buyer,
        uint256 ink,
        uint256 art
    ) internal override {
        super._collateralBought(vaultId, buyer, ink, art);
        contango.collateralBought(vaultId, buyer, ink, art);
    }

    function _auctionEnded(bytes12 vaultId, address owner) internal override {
        super._auctionEnded(vaultId, owner);
        contango.auctionEnded(vaultId, owner);
    }
}
