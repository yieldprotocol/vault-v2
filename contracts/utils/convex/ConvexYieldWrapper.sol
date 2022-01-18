// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.6;

import '@yield-protocol/vault-interfaces/ICauldron.sol';
import '@yield-protocol/vault-interfaces/DataTypes.sol';
import './ConvexStakingWrapper.sol';

/// @title Convex staking wrapper for Yield platform
/// @notice Enables use of convex LP positions as collateral while still receiving rewards
contract ConvexYieldWrapper is ConvexStakingWrapper {
    using TransferHelper for IERC20;

    /// @notice Mapping to keep track of the user & their vaults
    mapping(address => bytes12[]) public vaults;

    ICauldron public cauldron;

    /// @notice Event called when a vault is set for a user
    /// @param account The account for which vault is set
    /// @param vaultId The vaultId
    event VaultSet(address indexed account, bytes12 indexed vaultId);

    /// @notice Event called when a vault is removed for a user
    /// @param account The account for which vault is removed
    /// @param vaultId The vaultId to be removed
    event VaultRemoved(address indexed account, bytes12 indexed vaultId);

    constructor(
        address curveToken_,
        address convexToken_,
        address convexPool_,
        uint256 poolId_,
        address join_,
        ICauldron cauldron_,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ConvexStakingWrapper(curveToken_, convexToken_, convexPool_, poolId_, join_, name, symbol, decimals) {
        cauldron = cauldron_;
    }

    /// @notice Points the collateral vault to the join storing the wrappedCvx3Crv
    /// @param join_ Join which will store the wrappedCvx3Crv of the user
    function point(address join_) external auth {
        collateralVault = join_;
    }

    /// @notice Adds a vault to the user's vault list
    /// @param vaultId The vaulId being added
    function addVault(bytes12 vaultId) external {
        address account = cauldron.vaults(vaultId).owner;
        require(account != address(0), 'No owner for the vault');
        bytes12[] storage vaults_ = vaults[account];
        for (uint256 i = 0; i < vaults_.length; i++) {
            require(vaults_[i] != vaultId, 'already added');
        }
        vaults_.push(vaultId);
        vaults[account] = vaults_;
        emit VaultSet(account, vaultId);
    }

    /// @notice Remove a vault from the user's vault list
    /// @param vaultId The vaulId being added
    /// @param account The user from whom the vault needs to be removed
    function removeVault(bytes12 vaultId, address account) public {
        bytes12[] storage vaults_ = vaults[account];
        for (uint256 i = 0; i < vaults_.length; i++) {
            if (vaults_[i] == vaultId) {
                vaults_[i] = bytes12(0);
                emit VaultRemoved(account, vaultId);
                break;
            }
        }
        vaults[account] = vaults_;
    }

    /// @notice Get user's balance of collateral deposited in various vaults
    /// @param account_ User's address for which balance is requested
    /// @return User's balance of collateral
    function _getDepositedBalance(address account_) internal view override returns (uint256) {
        if (account_ == address(0) || account_ == collateralVault) {
            return 0;
        }

        bytes12[] memory userVault = vaults[account_];

        //add up all balances of all vaults
        uint256 collateral;
        DataTypes.Balances memory balance;
        for (uint256 i = 0; i < userVault.length; i++) {
            if (userVault[i] != bytes12(0)) {
                if (cauldron.vaults(userVault[i]).owner == account_) {
                    balance = cauldron.balances(userVault[i]);
                    collateral = collateral + balance.ink;
                }
            }
        }

        //add to balance of this token
        return _balanceOf[account_] + collateral;
    }

    /// @dev Wrap cvx3CRV held by this contract and forward it to the 'to' address
    /// @param to_ Address to send the wrapped token to
    /// @param from_ Address of the user whose token is being wrapped
    function wrap(address to_, address from_) external {
        uint256 amount_ = IERC20(convexToken).balanceOf(address(this));
        require(amount_ > 0, 'No cvx3CRV to wrap');
        _checkpoint([address(0), from_]);
        _mint(to_, amount_);
        IRewardStaking(convexPool).stake(amount_);
        emit Deposited(msg.sender, to_, amount_, false);
    }

    /// @dev Unwrap Wrapped cvx3CRV held by this contract, and send the cvx3Crv to the 'to' address
    /// @param to_ Address to send the unwrapped token to
    function unwrap(address to_) external {
        uint256 amount_ = _balanceOf[address(this)];
        require(amount_ > 0, 'No wcvx3CRV to unwrap');
        _checkpoint([address(0), to_]);
        _burn(address(this), amount_);
        IRewardStaking(convexPool).withdraw(amount_, false);
        IERC20(convexToken).safeTransfer(to_, amount_);

        emit Withdrawn(to_, amount_, false);
    }
}
