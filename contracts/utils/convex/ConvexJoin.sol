// SPDX-License-Identifier: MIT
// Original contract: https://github.com/convex-eth/platform/blob/main/contracts/contracts/wrappers/ConvexStakingWrapper.sol
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./interfaces/IRewardStaking.sol";
import "./CvxMining.sol";
import "../../Join.sol";

/// @notice Wrapper used to manage staking of Convex tokens
contract ConvexJoin is Join {
    using CastU256U128 for uint256;

    struct EarnedData {
        address token;
        uint256 amount;
    }

    struct RewardType {
        address reward_token;
        address reward_pool;
        uint128 reward_integral;
        uint128 reward_remaining;
        mapping(address => uint256) reward_integral_for;
        mapping(address => uint256) claimable_reward;
    }

    uint256 public managed_assets;
    mapping(address => bytes12[]) public vaults; // Mapping to keep track of the user & their vaults

    //constants/immutables
    address public constant convexBooster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address public curveToken;
    address public convexToken;
    address public convexPool;
    uint256 public convexPoolId;
    ICauldron public cauldron;

    //rewards
    RewardType[] public rewards;

    //management
    uint8 private _status = 1;

    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;

    event Deposited(address indexed _user, address indexed _account, uint256 _amount, bool _wrapped);
    event Withdrawn(address indexed _user, uint256 _amount, bool _unwrapped);

    /// @notice Event called when a vault is added for a user
    /// @param account The account for which vault is added
    /// @param vaultId The vaultId to be added
    event VaultAdded(address indexed account, bytes12 indexed vaultId);

    /// @notice Event called when a vault is removed for a user
    /// @param account The account for which vault is removed
    /// @param vaultId The vaultId to be removed
    event VaultRemoved(address indexed account, bytes12 indexed vaultId);

    constructor(
        address _curveToken,
        address _convexToken,
        address _convexPool,
        uint256 _poolId,
        ICauldron _cauldron,
    ) ERC20(name, symbol, decimals) {
        curveToken = _curveToken;
        convexToken = _convexToken;
        convexPool = _convexPool;
        convexPoolId = _poolId;
        cauldron = _cauldron;

        //add rewards
        addRewards();
        setApprovals();
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
        _;
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /// @notice Give maximum approval to the pool & convex booster contract to transfer funds from wrapper
    function setApprovals() public {
        address _curveToken = curveToken;
        IERC20(_curveToken).approve(convexBooster, 0);
        IERC20(_curveToken).approve(convexBooster, type(uint256).max);
        IERC20(convexToken).approve(convexPool, type(uint256).max);
    }

    /// ------ VAULT MANAGEMENT ------

    /// @notice Adds a vault to the user's vault list
    /// @param vaultId The id of the vault being added
    function addVault(bytes12 vaultId) external {
        address account = cauldron.vaults(vaultId).owner;
        require(cauldron.assets(cauldron.vaults(vaultId).ilkId) == address(this), "Vault is for different ilk");
        require(account != address(0), "No owner for the vault");
        bytes12[] storage vaults_ = vaults[account];
        uint256 vaultsLength = vaults_.length;

        for (uint256 i; i < vaultsLength; ++i) {
            require(vaults_[i] != vaultId, "Vault already added");
        }
        vaults_.push(vaultId);
        emit VaultAdded(account, vaultId);
    }

    /// @notice Remove a vault from the user's vault list
    /// @param vaultId The id of the vault being removed
    /// @param account The user from whom the vault needs to be removed
    function removeVault(bytes12 vaultId, address account) public {
        address owner = cauldron.vaults(vaultId).owner;
        require(account != owner, "vault belongs to account");
        bytes12[] storage vaults_ = vaults[account];
        uint256 vaultsLength = vaults_.length;
        for (uint256 i; i < vaultsLength; ++i) {
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

    /// @notice Get user's balance of collateral deposited in various vaults
    /// @param account_ User's address for which balance is requested
    /// @return User's balance of collateral
    function aggregatedAssetsOf(address account_) internal view override returns (uint256) {
        bytes12[] memory userVault = vaults[account_];

        //add up all balances of all vaults registered in the join and owned by the account
        uint256 collateral;
        DataTypes.Balances memory balance;
        uint256 userVaultLength = userVault.length;
        for (uint256 i; i < userVaultLength; ++i) {
            if (cauldron.vaults(userVault[i]).owner == account_) {
                balance = cauldron.balances(userVault[i]);
                collateral = collateral + balance.ink;
            }
        }

        return collateral;
    }

    /// ------ REWARDS MANAGEMENT ------

    /// @notice Adds reward tokens by reading the available rewards from the RewardStaking pool
    /// @dev CRV token is added as a reward by default
    function addRewards() public {
        address mainPool = convexPool;

        uint256 rewardsLength = rewards.length;

        if (rewardsLength == 0) {
            // We add cvx as a regular reward, but earnings will be calculated separately
            RewardType storage reward = rewards.push();
            reward.reward_token = cvx;
            // There is no reward pool for cvx

            RewardType storage reward = rewards.push();
            reward.reward_token = crv;
            reward.reward_pool = mainPool;
            rewardsLength = 2;
        }

        uint256 extraCount = IRewardStaking(mainPool).extraRewardsLength();

        uint256 startIndex = rewardsLength - 1;
        for (uint256 i = startIndex; i < extraCount; i++) {
            address extraPool = IRewardStaking(mainPool).extraRewards(i);
            RewardType storage reward = rewards.push();
            reward.reward_token = IRewardStaking(extraPool).rewardToken();
            reward.reward_pool = extraPool;
        }
    }

    /// ------ JOIN and EXIT ------

    /// @dev Take convex LP token and credit it to the `user` address.
    function join(address user, uint128 amount)
        external override
        auth
        returns (uint128)
    {
        require(amount > 0, "No convex token to wrap");

        _checkpoint(user);
        managed_assets += amount;

        _join(user, amount);
        IRewardStaking(convexPool).stake(amount);
        emit Deposited(msg.sender, user, amount, false);

        return (user, amount);
    }

    /// @dev Debit convex LP tokens held by this contract and send them to the `user` address.
    function exit(address user, uint128 amount)
        external override
        auth
        returns (uint128)
    {
        _checkpoint(user);
        managed_assets -= amount;
        
        IRewardStaking(convexPool).withdraw(amount, false);
        _exit(user, amount);
        emit Withdrawn(user, amount, false);

        return amount;
    }

    /// ------ REWARDS MATH ------

    /// @notice Calculates & upgrades the integral for distributing the reward token
    /// @param _index The index of the reward token for which the calculations are to be done
    /// @param _account Account for which the CvxIntegral has to be calculated
    /// @param _balance Balance of the accounts
    /// @param _supply Total supply of the wrapped token
    /// @param _isClaim Whether to claim the calculated rewards
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

        //do not give rewards to collateralVault or this contract
        if (_account != collateralVault && _account != address(this)) {
            //update user integrals
            uint256 userI = reward.reward_integral_for[_account];
            if (_isClaim || userI < rewardIntegral) {
                if (_isClaim) {
                    uint256 receiveable = reward.claimable_reward[_account] +
                        ((_balance * (uint256(rewardIntegral) - userI)) / 1e20);
                    if (receiveable > 0) {
                        reward.claimable_reward[_account] = 0;
                        TransferHelper.safeTransfer(IERC20(reward.reward_token), _account, receiveable);
                        unchecked {
                            bal -= receiveable;
                        }
                    }
                } else {
                    reward.claimable_reward[_account] =
                        reward.claimable_reward[_account] +
                        ((_balance * (uint256(rewardIntegral) - userI)) / 1e20);
                }
                reward.reward_integral_for[_account] = rewardIntegral;
            }
        }

        //update remaining reward here since balance could have changed if claiming
        if (bal != rewardRemaining) {
            reward.reward_remaining = uint128(bal);
        }
    }

    /// ------ CHECKPOINT AND CLAIM ------

    /// @notice Create a checkpoint for the supplied addresses by updating the reward integrals & claimable reward for them & claims the rewards
    /// @param _account The account for which checkpoints have to be calculated
    function _checkpoint(address _account, bool claim) internal {
        uint256 supply = managed_assets();
        uint256 depositedBalance;
        depositedBalance = aggregatedAssetsOf(_account); //only do first slot

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i; i < rewardCount; ++i) {
            _calcRewardIntegral(i, _account, depositedBalance, supply, claim);
        }
    }

    /// @notice Create a checkpoint for the supplied addresses by updating the reward integrals & claimable reward for them
    /// @param _account The accounts for which checkpoints have to be calculated
    function checkpoint(address _account) external returns (bool) {
        _checkpoint(_account, false);
        return true;
    }


    /// @notice Claim reward for the supplied account
    /// @param _account Address whose reward is to be claimed
    function getReward(address _account) external nonReentrant {
        //claim directly in checkpoint logic to save a bit of gas
        _checkpoint(_account, true);
    }

    /// @notice Get the amount of tokens the user has earned
    /// @param _account Address whose balance is to be checked
    /// @return claimable Array of earned tokens and their amount
    function earned(address _account) external view returns (EarnedData[] memory claimable) {
        uint256 supply = managed_assets();
        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount + 1);

        RewardType storage cvx_reward = rewards[0];

        for (uint256 i = 1; i < rewardCount; ++i) {
            RewardType storage reward = rewards[i];
            address rewardToken = reward.reward_token;

            //change in reward is current balance - remaining reward + earned
            uint256 bal = IERC20(rewardToken).balanceOf(address(this));
            uint256 d_reward = bal - reward.reward_remaining;
            d_reward = d_reward + IRewardStaking(reward.reward_pool).earned(address(this));

            uint256 I = reward.reward_integral;
            if (supply > 0) {
                I = I + (d_reward * 1e20) / supply;
            }

            uint256 newlyClaimable = (aggregatedAssetsOf(_account) * (I - reward.reward_integral_for[_account])) /
                1e20;
            claimable[i].amount = reward.claimable_reward[_account] + newlyClaimable;
            claimable[i].token = rewardToken;

            //calc cvx here
            if (rewardToken == crv) {
                claimable[rewardCount].amount =
                    cvx_reward.claimable_reward[_account] +
                    CvxMining.ConvertCrvToCvx(newlyClaimable);
                claimable[rewardCount].token = cvx;
            }
        }
        return claimable;
    }
}
