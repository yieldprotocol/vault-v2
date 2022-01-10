// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@yield-protocol/utils-v2/contracts/token/ERC20.sol';
import '@yield-protocol/vault-interfaces/DataTypes.sol';
import '@yield-protocol/utils-v2/contracts/token/TransferHelper.sol';
import '@yield-protocol/utils-v2/contracts/access/AccessControl.sol';

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

contract ConvexStakingWrapperYieldMock is ERC20, AccessControl {
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

    constructor(
        address convexToken_,
        address convexPool_,
        uint256 poolId_,
        address join_,
        ICauldron cauldron_,
        address crv_,
        address cvx_
    ) ERC20('StakedConvexToken', 'stkCvx', 18) {
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
    function addVault(bytes12 vault_) external {
        address account = cauldron.vaults(vault_).owner;
        require(account != address(0), 'No owner for the vault');
        bytes12[] storage userVault = vaults[account];
        for (uint256 i = 0; i < userVault.length; i++) {
            require(userVault[i] != vault_, 'already added');
        }
        userVault.push(vault_);
        vaults[account] = userVault;
    }

    function wrap(address _to) external {
        uint256 amount_ = IERC20(convexToken).balanceOf(address(this));
        require(amount_ > 0, 'No cvx3CRV to wrap');
        _checkpoint([address(0), tx.origin]);
        _mint(_to, amount_);
        IRewardStaking(convexPool).stake(amount_);
        emit Deposited(msg.sender, _to, amount_, false);
    }

    function unwrap(address to_) external {
        uint256 amount_ = _balanceOf[address(this)];
        require(amount_ > 0, 'No wcvx3CRV to unwrap');
        _checkpoint([address(0), to_]);
        _burn(address(this), amount_);
        IRewardStaking(convexPool).withdraw(amount_, false);
        IERC20(convexToken).safeTransfer(to_, amount_);

        emit Withdrawn(to_, amount_, false);
    }

    function getReward(address _account) external {
        //claim directly in checkpoint logic to save a bit of gas
        _checkpointAndClaim([_account, address(0)]);
    }

    function _checkpoint(address[2] memory _accounts) internal {
        //if shutdown, no longer checkpoint in case there are problems
        // if (isShutdown) return;

        uint256 supply = _totalSupply;
        uint256[2] memory depositedBalance;
        depositedBalance[0] = _getDepositedBalance(_accounts[0]);
        depositedBalance[1] = _getDepositedBalance(_accounts[1]);

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            _calcRewardIntegral(i, _accounts, depositedBalance, supply, false);
        }
        _calcCvxIntegral(_accounts, depositedBalance, supply, false);
    }

    function _checkpointAndClaim(address[2] memory _accounts) internal {
        uint256 supply = _totalSupply;
        uint256[2] memory depositedBalance;
        depositedBalance[0] = _getDepositedBalance(_accounts[0]); //only do first slot

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            _calcRewardIntegral(i, _accounts, depositedBalance, supply, true);
        }
        _calcCvxIntegral(_accounts, depositedBalance, supply, true);
    }

    /// @notice Get user's balance of collateral deposited in various vaults
    /// @param account_ User's address for which balance is requested
    /// @return User's balance of collateral
    function _getDepositedBalance(address account_) internal view returns (uint256) {
        if (account_ == address(0) || account_ == collateralVault) {
            return 0;
        }

        if (vaults[account_].length == 0) {
            return _balanceOf[account_];
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
        return _balanceOf[account_] + collateral;
    }

    function _calcCvxIntegral(
        address[2] memory _accounts,
        uint256[2] memory _balances,
        uint256 _supply,
        bool _isClaim
    ) internal {
        uint256 bal = IERC20(cvx).balanceOf(address(this));
        uint256 d_cvxreward = bal - cvx_reward_remaining;

        if (_supply > 0 && d_cvxreward > 0) {
            cvx_reward_integral = cvx_reward_integral + (d_cvxreward * 1e20) / (_supply);
        }

        //update user integrals for cvx
        for (uint256 u = 0; u < _accounts.length; u++) {
            //do not give rewards to address 0
            if (_accounts[u] == address(0)) continue;
            if (_accounts[u] == collateralVault) continue;

            uint256 userI = cvx_reward_integral_for[_accounts[u]];
            if (_isClaim || userI < cvx_reward_integral) {
                uint256 receiveable = cvx_claimable_reward[_accounts[u]] +
                    ((_balances[u] * (cvx_reward_integral - userI)) / 1e20);
                if (_isClaim) {
                    if (receiveable > 0) {
                        cvx_claimable_reward[_accounts[u]] = 0;
                        IERC20(cvx).safeTransfer(_accounts[u], receiveable);
                        bal = bal - receiveable;
                    }
                } else {
                    cvx_claimable_reward[_accounts[u]] = receiveable;
                }
                cvx_reward_integral_for[_accounts[u]] = cvx_reward_integral;
            }
        }

        //update reward total
        if (bal != cvx_reward_remaining) {
            cvx_reward_remaining = bal;
        }
    }

    function _calcRewardIntegral(
        uint256 _index,
        address[2] memory _accounts,
        uint256[2] memory _balances,
        uint256 _supply,
        bool _isClaim
    ) internal {
        RewardType storage reward = rewards[_index];

        //get difference in balance and remaining rewards
        //getReward is unguarded so we use reward_remaining to keep track of how much was actually claimed
        uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));
        // uint256 d_reward = bal-(reward.reward_remaining);

        if (_supply > 0 && bal - (reward.reward_remaining) > 0) {
            reward.reward_integral = reward.reward_integral + ((bal - reward.reward_remaining) * 1e20) / _supply;
        }

        //update user integrals
        for (uint256 u = 0; u < _accounts.length; u++) {
            //do not give rewards to address 0
            if (_accounts[u] == address(0)) continue;
            if (_accounts[u] == collateralVault) continue;

            uint256 userI = reward.reward_integral_for[_accounts[u]];
            if (_isClaim || userI < reward.reward_integral) {
                if (_isClaim) {
                    uint256 receiveable = reward.claimable_reward[_accounts[u]] +
                        ((_balances[u] * (uint256(reward.reward_integral) - userI)) / 1e20);
                    if (receiveable > 0) {
                        reward.claimable_reward[_accounts[u]] = 0;
                        IERC20(reward.reward_token).safeTransfer(_accounts[u], receiveable);
                        bal = bal - (receiveable);
                    }
                } else {
                    reward.claimable_reward[_accounts[u]] =
                        reward.claimable_reward[_accounts[u]] +
                        ((_balances[u] * (uint256(reward.reward_integral) - userI)) / 1e20);
                }
                reward.reward_integral_for[_accounts[u]] = reward.reward_integral;
            }
        }

        //update remaining reward here since balance could have changed if claiming
        if (bal != reward.reward_remaining) {
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

    function _transfer(
        address src,
        address dst,
        uint256 wad
    ) internal override returns (bool) {
        _checkpoint([address(0), tx.origin]);
        // _checkpoint([src, dst]);
        return super._transfer(src, dst, wad);
    }

    function user_checkpoint(address[2] calldata _accounts) external returns (bool) {
        _checkpoint([_accounts[0], _accounts[1]]);
        return true;
    }
}
