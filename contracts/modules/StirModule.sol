// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";


contract StirModule is AccessControl() {
    ICauldron public immutable cauldron;

    constructor (ICauldron cauldron_) {
        cauldron = cauldron_;
    }

    /// @dev Move collateral and debt between vaults.
    function stir(address initiator, bytes memory data)
        external
        auth
        returns (DataTypes.Balances memory, DataTypes.Balances memory)
    {
        (bytes12 from, bytes12 to, uint128 ink, uint128 art) = abi.decode(data, (bytes12, bytes12, uint128, uint128));
        if (ink > 0) require (cauldron.vaults(from).owner == initiator, "Only origin vault owner");
        if (art > 0) require (cauldron.vaults(to).owner == initiator, "Only destination vault owner");
        return cauldron.stir(from, to, ink, art);
    }
}