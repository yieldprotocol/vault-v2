// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

/// @title A contract that allows owner of a vault to give the vault
contract Giver is AccessControl {
    ICauldron public immutable cauldron;
    mapping(bytes6 => bool) public ilkBlacklist;

    /// @notice Event emitted after an ilk is blacklisted
    /// @param ilkId Ilkid to be blacklisted
    event IlkBlacklisted(bytes6 ilkId);

    constructor(ICauldron cauldron_) {
        cauldron = cauldron_;
    }

    /// @notice Function to blacklist
    /// @param ilkId the ilkId to be blacklisted
    /// @param set bool value to ban/unban an ilk
    function banIlk(bytes6 ilkId, bool set) external auth {
        ilkBlacklist[ilkId] = set;
        emit IlkBlacklisted(ilkId);
    }

    /// @notice A give function which allows the owner of vault to give the vault to another address
    /// @param vaultId The vaultId of the vault to be given
    /// @param receiver The address to which the vault is being given to
    /// @return vault The vault which has been given
    function give(bytes12 vaultId, address receiver) external returns (DataTypes.Vault memory vault) {
        vault = cauldron.vaults(vaultId);
        require(vault.owner == msg.sender, "msg.sender is not the owner");
        require(!ilkBlacklist[vault.ilkId], "ilk is blacklisted");
        vault = cauldron.give(vaultId, receiver);
    }
}
