// SPDX-License-Identifier: MIT
// Original contract: https://github.com/convex-eth/platform/blob/main/contracts/contracts/wrappers/ConvexStakingWrapper.sol
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./interfaces/IRewardStaking.sol";
import "./CvxMining.sol";

/// @notice Wrapper used to manage staking of Convex tokens
contract ConvexStakingWrapper is ERC20 {
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

    //constants/immutables
    uint256 public convexPoolId;
    address public constant convexBooster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address public curveToken;
    address public convexToken;
    address public convexPool;
    address public collateralVault;

    uint256 private constant CRV_INDEX = 0;
    uint256 private constant CVX_INDEX = 1;

    //management
    bool public isShutdown;
    uint8 private _status = 1;

    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;

    //rewards
    RewardType[] public rewards;
    mapping(address => uint256) public registeredRewards;

    event Deposited(address indexed _user, address indexed _account, uint256 _amount, bool _wrapped);
    event Withdrawn(address indexed _user, uint256 _amount, bool _unwrapped);

    constructor(
        address _curveToken,
        address _convexToken,
        address _convexPool,
        uint256 _poolId,
        address _vault,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol, decimals) {
        curveToken = _curveToken;
        convexToken = _convexToken;
        convexPool = _convexPool;
        convexPoolId = _poolId;
        collateralVault = _vault;

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

    /// @notice Adds reward tokens by reading the available rewards from the RewardStaking pool
    /// @dev CRV token is added as a reward by default
    function addRewards() public {
        address mainPool = convexPool;

        if (rewards.length == 0) {
            RewardType storage reward = rewards.push();
            reward.reward_token = crv;
            reward.reward_pool = mainPool;
            reward.reward_integral = 0;
            reward.reward_remaining = 0;

            reward = rewards.push();
            reward.reward_token = cvx;
            reward.reward_pool = address(0);
            reward.reward_integral = 0;
            reward.reward_remaining = 0;

            registeredRewards[crv] = CRV_INDEX + 1; //mark registered at index+1
            registeredRewards[cvx] = CVX_INDEX + 1; //mark registered at index+1
        }

        uint256 extraCount = IRewardStaking(mainPool).extraRewardsLength();
        for (uint256 i = 0; i < extraCount; i++) {
            address extraPool = IRewardStaking(mainPool).extraRewards(i);
            address extraToken = IRewardStaking(extraPool).rewardToken();
            if (extraToken == cvx) {
                //update cvx reward pool address
                rewards[CVX_INDEX].reward_pool = extraPool;
            } else if (registeredRewards[extraToken] == 0) {
                //add new token to list
                RewardType storage reward = rewards.push();
                reward.reward_token = IRewardStaking(extraPool).rewardToken();
                reward.reward_pool = extraPool;
                reward.reward_integral = 0;
                reward.reward_remaining = 0;

                registeredRewards[extraToken] = rewards.length; //mark registered at index+1
            }
        }
    }

    /// @notice Returns the length of the reward tokens added
    /// @return The count of reward tokens
    function rewardLength() external view returns (uint256) {
        return rewards.length;
    }

    /// @notice Get user's balance
    /// @param _account User's address for which balance is requested
    /// @return User's balance of collateral
    /// @dev Included here to allow inheriting contracts to override.
    function _getDepositedBalance(address _account) internal view virtual returns (uint256) {
        if (_account == address(0) || _account == collateralVault) {
            return 0;
        }
        //get balance from collateralVault

        return _balanceOf[_account];
    }

    /// @notice TotalSupply of wrapped token
    /// @return The total supply of wrapped token
    /// @dev This function is provided and marked virtual as convenience to future development
    function _getTotalSupply() internal view virtual returns (uint256) {
        return _totalSupply;
    }

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
            unchecked {
                rewardIntegral = rewardIntegral + ((bal - rewardRemaining) * 1e20) / _supply;
            }
            reward.reward_integral = rewardIntegral.u128();
        }

        //do not give rewards to collateralVault or this contract
        if (_account != collateralVault && _account != address(this)) {
            //update user integrals
            uint256 userI = reward.reward_integral_for[_account];
            if (_isClaim || userI < rewardIntegral) {
                unchecked {
                    if (_isClaim) {
                        uint256 receiveable = reward.claimable_reward[_account] +
                            ((_balance * (rewardIntegral - userI)) / 1e20);
                        if (receiveable > 0) {
                            reward.claimable_reward[_account] = 0;
                            TransferHelper.safeTransfer(IERC20(reward.reward_token), _account, receiveable);
                            bal -= receiveable;
                        }
                    } else {
                        reward.claimable_reward[_account] =
                            reward.claimable_reward[_account] +
                            ((_balance * (rewardIntegral - userI)) / 1e20);
                    }
                }
                reward.reward_integral_for[_account] = rewardIntegral;
            }
        }

        //update remaining reward here since balance could have changed if claiming
        if (bal != rewardRemaining) {
            reward.reward_remaining = bal.u128();
        }
    }

    /// @notice Create a checkpoint for the supplied addresses by updating the reward integrals & claimable reward for them
    /// @param _account The account for which checkpoints have to be calculated
    function _checkpoint(address _account) internal {
        //if shutdown, no longer checkpoint in case there are problems
        if (isShutdown) return;

        uint256 supply = _getTotalSupply();
        uint256 depositedBalance;
        depositedBalance = _getDepositedBalance(_account);

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i; i < rewardCount; ++i) {
            _calcRewardIntegral(i, _account, depositedBalance, supply, false);
        }
    }

    /// @notice Create a checkpoint for the supplied addresses by updating the reward integrals & claimable reward for them & claims the rewards
    /// @param _account The account for which checkpoints have to be calculated
    function _checkpointAndClaim(address _account) internal {
        uint256 supply = _getTotalSupply();
        uint256 depositedBalance;
        depositedBalance = _getDepositedBalance(_account); //only do first slot

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i; i < rewardCount; ++i) {
            _calcRewardIntegral(i, _account, depositedBalance, supply, true);
        }
    }

    /// @notice Create a checkpoint for the supplied addresses by updating the reward integrals & claimable reward for them
    /// @param _account The accounts for which checkpoints have to be calculated
    function user_checkpoint(address _account) external nonReentrant returns (bool) {
        _checkpoint(_account);
        return true;
    }

    /// @notice Get the balance of the user
    /// @param _account Address whose balance is to be checked
    /// @return The balance of the supplied address
    function totalBalanceOf(address _account) external view returns (uint256) {
        return _getDepositedBalance(_account);
    }

    /// @notice Get the amount of tokens the user has earned
    /// @param _account Address whose balance is to be checked
    /// @return claimable Array of earned tokens and their amount
    function earned(address _account) external view returns (EarnedData[] memory claimable) {
        uint256 supply = _getTotalSupply();
        // uint256 depositedBalance = _getDepositedBalance(_account);
        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            RewardType storage reward = rewards[i];

            if (reward.reward_pool == address(0)) {
                //cvx reward may not have a reward pool yet
                //so just add whats already been checkpointed
                claimable[i].amount = claimable[i].amount + reward.claimable_reward[_account];
                claimable[i].token = reward.reward_token;
                continue;
            }

            //change in reward is current balance - remaining reward + earned
            uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));
            uint256 d_reward = bal - reward.reward_remaining;
            d_reward = d_reward + IRewardStaking(reward.reward_pool).earned(address(this));

            uint256 I = reward.reward_integral;
            if (supply > 0) {
                I = I + (d_reward * 1e20) / supply;
            }

            uint256 newlyClaimable = (_getDepositedBalance(_account) * (I - (reward.reward_integral_for[_account]))) /
                (1e20);
            claimable[i].amount = claimable[i].amount + reward.claimable_reward[_account] + newlyClaimable;
            claimable[i].token = reward.reward_token;

            //calc cvx minted from crv and add to cvx claimables
            //note: crv is always index 0 so will always run before cvx
            if (i == CRV_INDEX) {
                //because someone can call claim for the pool outside of checkpoints, need to recalculate crv without the local balance
                I = reward.reward_integral;
                if (supply > 0) {
                    I = I + (IRewardStaking(reward.reward_pool).earned(address(this)) * 1e20) / supply;
                }
                newlyClaimable = (_getDepositedBalance(_account) * (I - reward.reward_integral_for[_account])) / 1e20;
                claimable[CVX_INDEX].amount = CvxMining.ConvertCrvToCvx(newlyClaimable);
                claimable[CVX_INDEX].token = cvx;
            }
        }
    }

    /// @notice Claim reward for the supplied account
    /// @param _account Address whose reward is to be claimed
    function getReward(address _account) external nonReentrant {
        //claim directly in checkpoint logic to save a bit of gas
        _checkpointAndClaim(_account);
    }
}
