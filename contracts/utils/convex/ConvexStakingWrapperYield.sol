//https://etherscan.io/address/0x3ba207c25a278524e1cc7faaea950753049072a4#code
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import '@yield-protocol/vault-interfaces/ICauldron.sol';
import '@yield-protocol/vault-interfaces/DataTypes.sol';
import './ConvexStakingWrapper.sol';

/// @title Convex staking wrapper for Yield platform
/// @notice Enables use of convex LP positions as collateral while still receiving rewards
contract ConvexStakingWrapperYield is ConvexStakingWrapper {
    using TransferHelper for IERC20;

    /// @notice Mapping to keep track of the user & their vaults
    mapping(address => bytes12[]) public vaults;

    ICauldron public cauldron;

    /// @notice Event called when a vault is set for a user
    /// @param account The account for which vault is set
    /// @param vault The vaultId
    event VaultSet(address indexed account, bytes12 indexed vault);

    constructor(
        address curveToken_,
        address convexToken_,
        address convexPool_,
        uint256 poolId_,
        address join_,
        ICauldron cauldron_
    ) {
        name = string(abi.encodePacked('Staked ', ERC20(convexToken_).name(), ' Yield'));
        symbol = string(abi.encodePacked('stk', ERC20(convexToken_).symbol(), '-yield'));
        isShutdown = false;
        isInit = true;
        curveToken = curveToken_;
        convexToken = convexToken_;
        convexPool = convexPool_;
        convexPoolId = poolId_;
        collateralVault = join_; //TODO: Add the join address
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

    /// @notice Unwraps the token and returns the supplied cvx token to the user
    /// @dev Have added auth to this function to prevent somebody else to withdraw tokens for an account they don't own
    /// @param amount_ The amount of tokens to withdraw
    /// @param account_ The account for which to withdraw
    function withdrawFor(uint256 amount_, address account_) external nonReentrant auth {
        //dont need to call checkpoint since _burn() will
        if (amount_ > 0) {
            _burn(account_, amount_);
            IRewardStaking(convexPool).withdraw(amount_, false);
            IERC20(convexToken).safeTransfer(account_, amount_);
        }

        emit Withdrawn(account_, amount_, false);
    }

    /// @notice Stake for a user
    /// @param amount_ The amount to stake
    /// @param account_ The address for which to stake
    /// @param to_ The address to which the wrapped token would be sent
    function stakeFor(
        uint256 amount_,
        address account_,
        address to_
    ) external nonReentrant {
        require(!isShutdown, 'shutdown');

        //dont need to call checkpoint since _mint() will
        if (amount_ > 0) {
            _mint(to_, amount_);
            IERC20(convexToken).safeTransferFrom(account_, address(this), amount_);
            IRewardStaking(convexPool).stake(amount_);
        }

        emit Deposited(msg.sender, to_, amount_, false);
    }
}
