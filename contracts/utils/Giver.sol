// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

/// @title A contract that allows owner of a vault to give the vault
contract Giver is AccessControl {
    ICauldron public immutable cauldron;
    mapping(bytes6 => bool) public bannedIlks;

    /// @notice Event emitted after an ilk is banned
    /// @param ilkId Ilkid to be banned
    event IlkBanned(bytes6 ilkId);

    constructor(ICauldron cauldron_) {
        cauldron = cauldron_;
    }

    /// @notice Function to ban
    /// @param ilkId the ilkId to be banned
    /// @param set bool value to ban/unban an ilk
    function banIlk(bytes6 ilkId, bool set) external auth {
        bannedIlks[ilkId] = set;
        emit IlkBanned(ilkId);
    }

    /// @notice A give function which allows the owner of vault to give the vault to another address
    /// @param vaultId The vaultId of the vault to be given
    /// @param receiver The address to which the vault is being given to
    /// @return vault The vault which has been given
    function give(bytes12 vaultId, address receiver) external returns (DataTypes.Vault memory vault) {
        vault = cauldron.vaults(vaultId);
        require(vault.owner == msg.sender, "msg.sender is not the owner");
        require(!bannedIlks[vault.ilkId], "ilk is banned");
        vault = cauldron.give(vaultId, receiver);
    }

    /// @notice A give function which allows the authenticated address to give the vault of any user to another address
    /// @param vaultId The vaultId of the vault to be given
    /// @param receiver The address to which the vault is being given to
    /// @return vault The vault which has been given
    function seize(bytes12 vaultId, address receiver) external auth returns (DataTypes.Vault memory vault) {
        vault = cauldron.vaults(vaultId);
        require(!bannedIlks[vault.ilkId], "ilk is banned");
        vault = cauldron.give(vaultId, receiver);
    }
}
