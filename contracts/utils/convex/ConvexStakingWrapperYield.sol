//https://etherscan.io/address/0x3ba207c25a278524e1cc7faaea950753049072a4#code
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
pragma experimental ABIEncoderV2;

import '@yield-protocol/vault-interfaces/ICauldron.sol';
import '@yield-protocol/vault-interfaces/DataTypes.sol';
import './ConvexStakingWrapper.sol';

/// @title Convex staking wrapper for Yield platform
/// @notice Enables use of convex LP positions as collateral while still receiving rewards
contract ConvexStakingWrapperYield is ConvexStakingWrapper {
    using TransferHelper for IERC20;

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

    function setCollateralVault(address join_) external {
        require(msg.sender==owner,'Only owner can set vault');
        collateralVault = join_;
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
            return _balanceOf[account_];
        }
        bytes12[] memory userVault = vaults[account_];

        //add up all balances of all vaults
        uint256 collateral;
        DataTypes.Balances memory balance;
        for (uint256 i = 0; i < userVault.length; i++) {
            balance = cauldron.balances(userVault[i]);
            collateral = collateral + balance.ink;
        }

        //add to balance of this token
        return _balanceOf[account_] + collateral;
    }

    function withdrawFor(uint256 _amount,address _account) external nonReentrant {
        //dont need to call checkpoint since _burn() will
        if (_amount > 0) {
            _burn(_account, _amount);
            IRewardStaking(convexPool).withdraw(_amount, false);
            IERC20(convexToken).safeTransfer(_account, _amount);
        }

        emit Withdrawn(_account, _amount, false);
    }

    function stakeFor(uint256 _amount,address account, address _to) external nonReentrant {
        require(!isShutdown, 'shutdown');

        //dont need to call checkpoint since _mint() will
        if (_amount > 0) {
            _mint(_to, _amount);
            IERC20(convexToken).safeTransferFrom(account, address(this), _amount);
            IRewardStaking(convexPool).stake(_amount);
        }

        emit Deposited(msg.sender, _to, _amount, false);
    }
}
