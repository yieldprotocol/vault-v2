//https://etherscan.io/address/0x3ba207c25a278524e1cc7faaea950753049072a4#code
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
pragma experimental ABIEncoderV2;

import './ConvexStakingWrapper.sol';

struct Balances {
    uint128 art; // Debt amount
    uint128 ink; // Collateral amount
}

struct Vault {
    address owner;
    bytes6 seriesId; // Each vault is related to only one series, which also determines the underlying.
    bytes6 ilkId; // Asset accepted as collateral
}

interface ICauldron {
    /// @dev Each vault records debt and collateral balances_.
    function balances(bytes12 vault) external view returns (Balances memory);

    /// @dev A user can own one or more Vaults, with each vault being able to borrow from a single series.
    function vaults(bytes12 vault) external view returns (Vault memory);
}

/// @title Convex staking wrapper for Yield platform
/// @notice Enables use of convex LP positions as collateral while still receiving rewards
contract ConvexStakingWrapperYield is ConvexStakingWrapper {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice Mapping to keep track of the user & their vaults
    mapping(address => bytes12[]) public vaults;

    ICauldron cauldron;

    /// @notice Event called when a vault is set for a user
    /// @param account The account for which vault is set
    /// @param vault The vaultId
    event VaultSet(address account, bytes12 vault);

    constructor(
        address curveToken_,
        address convexToken_,
        address convexPool_,
        uint256 poolId_,
        address join_,
        ICauldron cauldron_,
        address timelock_
    ) {
        owner = address(timelock_);
        emit OwnershipTransferred(address(0), owner);
        _tokenname = string(abi.encodePacked('Staked ', ERC20(convexToken_).name(), ' Yield'));
        _tokensymbol = string(abi.encodePacked('stk', ERC20(convexToken_).symbol(), '-yield'));
        isShutdown = false;
        isInit = true;
        curveToken = curveToken_;
        convexToken = convexToken_;
        convexPool = convexPool_;
        convexPoolId = poolId_;
        collateralVault = join_; //TODO: Add the join address
        cauldron = cauldron_;

        //add rewards
        addRewards();
        setApprovals();
    }

    /// @notice Adds a vault to the user's vault list
    /// @param vault_ The vaulId being added
    function addVault(bytes12 vault_) external {
        address account = cauldron.vaults(vault_).owner;
        require(account != address(0), 'No owner for the vault');
        bytes12[] storage userVault = vaults[account];
        for (uint256 i = 0; i < userVault.length; i++) {
            require(userVault[i] != vault_, 'already added');
        }
        userVault.push(vault_);
        vaults[account] = userVault;
        emit VaultSet(account, vault_);
    }

    /// @notice Get user's balance of collateral deposited in various vaults
    /// @param account_ User's address for which balance is requested
    /// @return User's balance of collateral
    function _getDepositedBalance(address account_) internal view override returns (uint256) {
        if (account_ == address(0) || account_ == collateralVault) {
            return 0;
        }

        if (vaults[account_].length == 0) {
            return balanceOf(account_);
        }
        bytes12[] memory userVault = vaults[account_];

        //add up all balances of all vaults
        uint256 collateral;
        Balances memory balance;
        for (uint256 i = 0; i < userVault.length; i++) {
            balance = cauldron.balances(userVault[i]);
            collateral = collateral + balance.ink;
        }

        //add to balance of this token
        return balanceOf(account_) + collateral;
    }
}
