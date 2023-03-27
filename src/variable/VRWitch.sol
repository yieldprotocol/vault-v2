// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "./interfaces/IVRCauldron.sol";
import "../WitchBase.sol";
import { UUPSUpgradeable } from "openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title  The Witch is a DataTypes.Auction/Liquidation Engine for the Yield protocol
/// @notice The Witch grabs under-collateralised vaults, replacing the owner by itself. Then it sells
/// the vault collateral in exchange for underlying to pay its debt. The amount of collateral
/// given increases over time, until it offers to sell all the collateral for underlying to pay
/// all the debt. The auction is held open at the final price indefinitely.
/// @dev After the debt is settled, the Witch returns the vault to its original owner.
contract VRWitch is WitchBase, UUPSUpgradeable {
    using Cast for uint256;

    // If we would copy the code from WitchBase here we could make the ladle immutable,
    // saving some gas. We don't do that to avoid code duplication and minimize the code to be audited.

    bool public initialized;

    constructor(ICauldron cauldron_, ILadle ladle_) WitchBase(cauldron_, ladle_) {
        // See https://medium.com/immunefi/wormhole-uninitialized-proxy-bugfix-review-90250c41a43a
        initialized = true; // Lock the implementation contract
    }

    // ======================================================================
    // =                    Upgradability management functions                    =
    // ======================================================================

    /// @dev Give the ROOT role and create a LOCK role with itself as the admin role and no members. 
    /// Calling setRoleAdmin(msg.sig, LOCK) means no one can grant that msg.sig role anymore.
    /// Set the ladle as well.
    function initialize (ILadle ladle_, address root_) public {
        require(!initialized, "Already initialized");
        initialized = true;             // On an uninitialized contract, no governance functions can be executed, because no one has permission to do so
        
        ladle = ladle_;
        auctioneerReward = ONE_PERCENT;

        _grantRole(ROOT, root_);   // Grant ROOT
        _setRoleAdmin(LOCK, LOCK);      // Create the LOCK role by setting itself as its own admin, creating an independent role tree
    }

    /// @dev Allow to set a new implementation
    function _authorizeUpgrade(address newImplementation) internal override auth {}

    // ======================================================================
    // =                    Auction management functions                    =
    // ======================================================================

    /// @dev Put an under-collateralised vault up for liquidation
    /// @param vaultId Id of the vault to liquidate
    /// @param to Receiver of the auctioneer reward
    /// @return auction_ Info associated to the auction itself
    /// @return vault Vault that's being auctioned
    function auction(bytes12 vaultId, address to)
        external
        beforeAshes
        returns (
            DataTypes.Auction memory auction_,
            VRDataTypes.Vault memory vault
        )
    {
        vault = IVRCauldron(address(cauldron)).vaults(vaultId);

        DataTypes.Line memory line;
        (auction_, line) = _calcAuctionParameters(
            vaultId,
            vault.baseId,
            vault.ilkId,
            bytes6(0),
            vault.owner,
            to
        );

        vault = IVRCauldron(address(cauldron)).give(vaultId, address(this));
        emit Auctioned(
            vaultId,
            auction_,
            line.duration,
            line.collateralProportion
        );
    }

    // ======================================================================
    // =                          Bidding functions                         =
    // ======================================================================

    /// @notice Returns debt that could be paid given the maxBaseIn
    function _debtFromBase(DataTypes.Auction memory auction_, uint128 maxBaseIn)
        internal
        override
        returns (uint256 artIn)
    {
        artIn = cauldron.debtFromBase(auction_.baseId, maxBaseIn);
    }

    /// @notice Returns base that could be paid given the artIn
    function _debtToBase(DataTypes.Auction memory auction_, uint128 artIn)
        internal
        override
        returns (uint256 baseIn)
    {
        baseIn = cauldron.debtToBase(auction_.baseId, artIn);
    }

    // ======================================================================
    // =                         Quoting functions                          =
    // ======================================================================

    function _getVaultDetailsAndDebt(bytes12 vaultId)
        internal
        view
        override
        returns (VaultBalanceDebtData memory details)
    {
        VRDataTypes.Vault memory vault = IVRCauldron(address(cauldron)).vaults(
            vaultId
        );

        details.ilkId = vault.ilkId;
        details.baseId = vault.baseId;
        details.seriesId = bytes6(0);
        details.owner = vault.owner;
        details.balances = cauldron.balances(vaultId);
        details.debt = cauldron.debt(vault.baseId, vault.ilkId);
    }
}
