// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

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

    /// @dev Assets available in Cauldron.
    function assets(bytes6 assetsId) external view returns (address);
}

interface IRewardStaking {
    function stakeFor(address, uint256) external;

    function stake(uint256) external;

    function withdraw(uint256 amount, bool claim) external;

    function withdrawAndUnwrap(uint256 amount, bool claim) external;

    function earned(address account) external view returns (uint256);

    function getReward() external;

    function getReward(address _account, bool _claimExtras) external;

    function extraRewardsLength() external view returns (uint256);

    function extraRewards(uint256 _pid) external view returns (address);

    function rewardToken() external view returns (address);

    function balanceOf(address _account) external view returns (uint256);
}

contract ConvexYieldWrapperMock is ERC20, AccessControl {
    using TransferHelper for IERC20;

    struct RewardType {
        address reward_token;
        address reward_pool;
        uint256 reward_integral;
        uint256 reward_remaining;
        mapping(address => uint256) reward_integral_for;
        mapping(address => uint256) claimable_reward;
    }

    mapping(address => bytes12[]) public vaults;
    ICauldron cauldron;

    uint256 public cvx_reward_integral;
    uint256 public cvx_reward_remaining;
    mapping(address => uint256) public cvx_reward_integral_for;
    mapping(address => uint256) public cvx_claimable_reward;

    //constants/immutables
    // address public constant convexBooster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public crv;
    address public cvx;
    address public convexToken;
    address public convexPool;
    uint256 public convexPoolId;
    address public collateralVault;

    //rewards
    RewardType[] public rewards;

    event Deposited(address indexed _user, address indexed _account, uint256 _amount, bool _wrapped);
    event Withdrawn(address indexed _user, uint256 _amount, bool _unwrapped);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Event called when a vault is added for a user
    /// @param account The account for which vault is added
    /// @param vaultId The vaultId to be added
    event VaultAdded(address indexed account, bytes12 indexed vaultId);

    /// @notice Event called when a vault is removed for a user
    /// @param account The account for which vault is removed
    /// @param vaultId The vaultId to be removed
    event VaultRemoved(address indexed account, bytes12 indexed vaultId);

    /// @notice Event called when tokens are rescued from the contract
    /// @param token Address of the token being rescued
    /// @param amount Amount of the token being rescued
    /// @param destination Address to which the rescued tokens have been sent
    event Recovered(address indexed token, uint256 amount, address indexed destination);

    constructor(
        address convexToken_,
        address convexPool_,
        uint256 poolId_,
        address join_,
        ICauldron cauldron_,
        address crv_,
        address cvx_
    ) ERC20("StakedConvexToken", "stkCvx", 18) {
        convexToken = convexToken_;
        convexPool = convexPool_;
        convexPoolId = poolId_;
        collateralVault = join_; //TODO: Add the join address
        cauldron = cauldron_;
        crv = crv_;
        cvx = cvx_;
        setApprovals();
        addRewards();
    }

    function setCauldron(ICauldron _cauldron) external {
        cauldron = _cauldron;
    }

    // Set the locations of vaults where the user's funds have been deposited & the accounting is kept
    function addVault(bytes12 vaultId) external {
        address account = cauldron.vaults(vaultId).owner;
        require(cauldron.assets(cauldron.vaults(vaultId).ilkId) == address(this), "Vault is for different ilk");
        require(account != address(0), "No owner for the vault");
        bytes12[] storage vaults_ = vaults[account];
        uint256 vaultsLength = vaults_.length;

        for (uint256 i = 0; i < vaultsLength; i++) {
            require(vaults_[i] != vaultId, "Vault already added");
        }
        vaults_.push(vaultId);
        emit VaultAdded(account, vaultId);
    }

    /// @notice Remove a vault from the user's vault list
    /// @param vaultId The vaulId being removed
    /// @param account The user from whom the vault needs to be removed
    function removeVault(bytes12 vaultId, address account) public {
        address owner = cauldron.vaults(vaultId).owner;
        require(account == owner, "Vault doesn't belong to account");
        bytes12[] storage vaults_ = vaults[account];
        uint256 vaultsLength = vaults_.length;
        for (uint256 i = 0; i < vaultsLength; i++) {
            if (vaults_[i] == vaultId) {
                bool isLast = i == vaultsLength - 1;
                if (!isLast) {
                    vaults_[i] = vaults_[vaultsLength - 1];
                }
                vaults_.pop();
                emit VaultRemoved(account, vaultId);
                return;
            }
        }
        revert("Vault not found");
    }

    function wrap(address from_) external {
        uint256 amount_ = IERC20(convexToken).balanceOf(address(this));
        require(amount_ > 0, "No cvx3CRV to wrap");
        _checkpoint(from_);
        _mint(collateralVault, amount_);
        IRewardStaking(convexPool).stake(amount_);
        emit Deposited(msg.sender, collateralVault, amount_, false);
    }

    function unwrap(address to_) external {
        uint256 amount_ = _balanceOf[address(this)];
        require(amount_ > 0, "No wcvx3CRV to unwrap");

        _checkpoint(to_);
        _burn(address(this), amount_);
        IRewardStaking(convexPool).withdraw(amount_, false);
        IERC20(convexToken).safeTransfer(to_, amount_);

        emit Withdrawn(to_, amount_, false);
    }

    function getReward(address _account) external {
        //claim directly in checkpoint logic to save a bit of gas
        _checkpointAndClaim(_account);
    }

    function _checkpoint(address _account) internal {
        uint256 supply = _totalSupply;
        uint256 depositedBalance;
        depositedBalance = _getDepositedBalance(_account);

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            _calcRewardIntegral(i, _account, depositedBalance, supply, false);
        }
        _calcCvxIntegral(_account, depositedBalance, supply, false);
    }

    function _checkpointAndClaim(address _account) internal {
        uint256 supply = _totalSupply;
        uint256 depositedBalance;
        depositedBalance = _getDepositedBalance(_account); //only do first slot

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            _calcRewardIntegral(i, _account, depositedBalance, supply, true);
        }
        _calcCvxIntegral(_account, depositedBalance, supply, true);
    }

    /// @notice Get user's balance of collateral deposited in various vaults
    /// @param account_ User's address for which balance is requested
    /// @return User's balance of collateral
    function _getDepositedBalance(address account_) internal view returns (uint256) {
        if (account_ == address(0) || account_ == collateralVault) {
            return 0;
        }

        bytes12[] memory userVault = vaults[account_];

        //add up all balances of all vaults
        uint256 collateral;
        Balances memory balance;
        for (uint256 i = 0; i < userVault.length; i++) {
            if (cauldron.vaults(userVault[i]).owner == account_) {
                balance = cauldron.balances(userVault[i]);
                collateral = collateral + balance.ink;
            }
        }

        //add to balance of this token
        return _balanceOf[account_] + collateral;
    }

    function _calcCvxIntegral(
        address _account,
        uint256 _balance,
        uint256 _supply,
        bool _isClaim
    ) internal {
        uint256 bal = IERC20(cvx).balanceOf(address(this));
        uint256 cvxRewardRemaining = cvx_reward_remaining;
        uint256 d_cvxreward = bal - cvxRewardRemaining;
        uint256 cvxRewardIntegral = cvx_reward_integral;

        if (_supply > 0 && d_cvxreward > 0) {
            cvxRewardIntegral = cvxRewardIntegral + (d_cvxreward * 1e20) / (_supply);
            cvx_reward_integral = cvxRewardIntegral;
        }

        //update user integrals for cvx
        //do not give rewards to address 0
        if (_account == address(0) || _account == collateralVault) {
            if (bal != cvxRewardRemaining) {
                cvx_reward_remaining = bal;
            }
            return;
        }

        uint256 userI = cvx_reward_integral_for[_account];
        if (_isClaim || userI < cvxRewardIntegral) {
            uint256 receiveable = cvx_claimable_reward[_account] + ((_balance * (cvxRewardIntegral - userI)) / 1e20);
            if (_isClaim) {
                if (receiveable > 0) {
                    cvx_claimable_reward[_account] = 0;
                    IERC20(cvx).safeTransfer(_account, receiveable);
                    bal = bal - (receiveable);
                }
            } else {
                cvx_claimable_reward[_account] = receiveable;
            }
            cvx_reward_integral_for[_account] = cvxRewardIntegral;
        }

        //update reward total
        if (bal != cvxRewardRemaining) {
            cvx_reward_remaining = bal;
        }
    }

    function _calcRewardIntegral(
        uint256 _index,
        address _account,
        uint256 _balance,
        uint256 _supply,
        bool _isClaim
    ) internal {
        RewardType storage reward = rewards[_index];

        uint256 rewardIntegral = reward.reward_integral;
        uint256 rewardRemaining = reward.reward_remaining;

        //get difference in balance and remaining rewards
        //getReward is unguarded so we use reward_remaining to keep track of how much was actually claimed
        uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));
        if (_supply > 0 && (bal - rewardRemaining) > 0) {
            rewardIntegral = uint128(rewardIntegral) + uint128(((bal - rewardRemaining) * 1e20) / _supply);
            reward.reward_integral = uint128(rewardIntegral);
        }

        //update user integrals
        //do not give rewards to address 0
        if (_account == address(0) || _account == collateralVault) {
            if (bal != rewardRemaining) {
                reward.reward_remaining = uint128(bal);
            }
            return;
        }

        uint256 userI = reward.reward_integral_for[_account];
        if (_isClaim || userI < rewardIntegral) {
            if (_isClaim) {
                uint256 receiveable = reward.claimable_reward[_account] +
                    ((_balance * (uint256(rewardIntegral) - userI)) / 1e20);
                if (receiveable > 0) {
                    reward.claimable_reward[_account] = 0;
                    IERC20(reward.reward_token).safeTransfer(_account, receiveable);
                    bal = bal - receiveable;
                }
            } else {
                reward.claimable_reward[_account] =
                    reward.claimable_reward[_account] +
                    ((_balance * (uint256(rewardIntegral) - userI)) / 1e20);
            }
            reward.reward_integral_for[_account] = rewardIntegral;
        }

        //update remaining reward here since balance could have changed if claiming
        if (bal != rewardRemaining) {
            reward.reward_remaining = uint128(bal);
        }
    }

    function setApprovals() public {
        //Removing this as we would be simulating the depositing and the rewards that are received
        // IERC20(curveToken).approve(convexBooster, 0);
        // IERC20(curveToken).approve(convexBooster, type(uint256).max);
        IERC20(convexToken).approve(convexPool, 0);
        IERC20(convexToken).approve(convexPool, type(uint256).max);
    }

    function addRewards() public {
        address mainPool = convexPool;

        if (rewards.length == 0) {
            RewardType storage reward = rewards.push();
            reward.reward_token = crv;
            reward.reward_pool = mainPool;
            reward.reward_integral = 0;
            reward.reward_remaining = 0;
        }

        // uint256 extraCount = IRewardStaking(mainPool).extraRewardsLength();
        // uint256 startIndex = rewards.length - 1;
        // for (uint256 i = startIndex; i < extraCount; i++) {
        //     address extraPool = IRewardStaking(mainPool).extraRewards(i);
        //     RewardType storage reward = rewards.push();
        //     reward.reward_token = IRewardStaking(extraPool).rewardToken();
        //     reward.reward_pool = extraPool;
        //     reward.reward_integral = 0;
        //     reward.reward_remaining = 0;
        // }
    }

    function point(address join_) public {
        collateralVault = join_;
    }

    function user_checkpoint(address _account) external returns (bool) {
        _checkpoint(_account);
        return true;
    }
}
