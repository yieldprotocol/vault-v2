// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@yield-protocol/utils-v2/contracts/token/IERC20.sol';
import '@yield-protocol/utils-v2/contracts/token/ERC20.sol';
import '@yield-protocol/utils-v2/contracts/access/AccessControl.sol';
import '@yield-protocol/utils-v2/contracts/token/TransferHelper.sol';
import './interfaces/IRewardStaking.sol';
import './interfaces/IConvexDeposits.sol';
import './interfaces/ICvx.sol';

library CvxMining {
    ICvx public constant cvx = ICvx(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    function ConvertCrvToCvx(uint256 _amount) internal view returns (uint256) {
        uint256 supply = cvx.totalSupply();
        uint256 reductionPerCliff = cvx.reductionPerCliff();
        uint256 totalCliffs = cvx.totalCliffs();
        uint256 maxSupply = cvx.maxSupply();

        uint256 cliff = supply / reductionPerCliff;
        //mint if below total cliffs
        if (cliff < totalCliffs) {
            //for reduction% take inverse of current cliff
            uint256 reduction = totalCliffs - cliff;
            //reduce
            _amount = (_amount * reduction) / totalCliffs;

            //supply cap check
            uint256 amtTillMax = maxSupply - supply;
            if (_amount > amtTillMax) {
                _amount = amtTillMax;
            }

            //mint
            return _amount;
        }
        return 0;
    }
}

contract ConvexStakingWrapper is ERC20, AccessControl {
    using TransferHelper for IERC20;

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

    uint256 public cvx_reward_integral;
    uint256 public cvx_reward_remaining;
    mapping(address => uint256) public cvx_reward_integral_for;
    mapping(address => uint256) public cvx_claimable_reward;

    //constants/immutables
    address public constant convexBooster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address public curveToken;
    address public convexToken;
    address public convexPool;
    uint256 public convexPoolId;
    address public collateralVault;

    //rewards
    RewardType[] public rewards;

    //management
    bool public isShutdown;
    bool public isInit;
    bool private _status;

    bool private constant _NOT_ENTERED = false;
    bool private constant _ENTERED = true;

    event Deposited(address indexed _user, address indexed _account, uint256 _amount, bool _wrapped);
    event Withdrawn(address indexed _user, uint256 _amount, bool _unwrapped);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() ERC20('StakedConvexToken', 'stkCvx', 18) {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, 'ReentrancyGuard: reentrant call');
        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
        _;
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    function shutdown() external auth {
        isShutdown = true;
    }

    function setApprovals() public {
        IERC20(curveToken).approve(convexBooster, 0);
        IERC20(curveToken).approve(convexBooster, type(uint256).max);
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

        uint256 extraCount = IRewardStaking(mainPool).extraRewardsLength();
        uint256 startIndex = rewards.length - 1;
        for (uint256 i = startIndex; i < extraCount; i++) {
            address extraPool = IRewardStaking(mainPool).extraRewards(i);
            RewardType storage reward = rewards.push();
            reward.reward_token = IRewardStaking(extraPool).rewardToken();
            reward.reward_pool = extraPool;
            reward.reward_integral = 0;
            reward.reward_remaining = 0;
        }
    }

    function rewardLength() external view returns (uint256) {
        return rewards.length;
    }

    function _getDepositedBalance(address _account) internal view virtual returns (uint256) {
        if (_account == address(0) || _account == collateralVault) {
            return 0;
        }
        //get balance from collateralVault

        return _balanceOf[_account];
    }

    function _getTotalSupply() internal view virtual returns (uint256) {
        return _totalSupply;
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
                        bal = bal - (receiveable);
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
        if (_supply > 0 && (bal - reward.reward_remaining) > 0) {
            reward.reward_integral =
                reward.reward_integral +
                uint128(((bal - reward.reward_remaining) * 1e20) / _supply);
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
                        bal = bal - receiveable;
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

    function _checkpoint(address[2] memory _accounts) internal {
        //if shutdown, no longer checkpoint in case there are problems
        if (isShutdown) return;

        uint256 supply = _getTotalSupply();
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
        uint256 supply = _getTotalSupply();
        uint256[2] memory depositedBalance;
        depositedBalance[0] = _getDepositedBalance(_accounts[0]); //only do first slot

        IRewardStaking(convexPool).getReward(address(this), true);

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            _calcRewardIntegral(i, _accounts, depositedBalance, supply, true);
        }
        _calcCvxIntegral(_accounts, depositedBalance, supply, true);
    }

    function user_checkpoint(address[2] calldata _accounts) external returns (bool) {
        _checkpoint([_accounts[0], _accounts[1]]);
        return true;
    }

    function totalBalanceOf(address _account) external view returns (uint256) {
        return _getDepositedBalance(_account);
    }

    function earned(address _account) external view returns (EarnedData[] memory claimable) {
        uint256 supply = _getTotalSupply();
        // uint256 depositedBalance = _getDepositedBalance(_account);
        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount + 1);

        for (uint256 i = 0; i < rewardCount; i++) {
            RewardType storage reward = rewards[i];

            //change in reward is current balance - remaining reward + earned
            uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));
            uint256 d_reward = bal - reward.reward_remaining;
            d_reward = d_reward + IRewardStaking(reward.reward_pool).earned(address(this));

            uint256 I = reward.reward_integral;
            if (supply > 0) {
                I = I + (d_reward * 1e20) / supply;
            }

            uint256 newlyClaimable = (_getDepositedBalance(_account) * (I - reward.reward_integral_for[_account])) /
                1e20;
            claimable[i].amount = reward.claimable_reward[_account] + newlyClaimable;
            claimable[i].token = reward.reward_token;

            //calc cvx here
            if (reward.reward_token == crv) {
                claimable[rewardCount].amount =
                    cvx_claimable_reward[_account] +
                    CvxMining.ConvertCrvToCvx(newlyClaimable);
                claimable[rewardCount].token = cvx;
            }
        }
        return claimable;
    }

    function getReward(address _account) external {
        //claim directly in checkpoint logic to save a bit of gas
        _checkpointAndClaim([_account, address(0)]);
    }

    //deposit a curve token
    function deposit(uint256 _amount, address _to) external nonReentrant {
        require(!isShutdown, 'shutdown');

        //dont need to call checkpoint since _mint() will

        if (_amount > 0) {
            _mint(_to, _amount);
            IERC20(curveToken).safeTransferFrom(msg.sender, address(this), _amount);
            IConvexDeposits(convexBooster).deposit(convexPoolId, _amount, true);
        }

        emit Deposited(msg.sender, _to, _amount, true);
    }

    //stake a convex token
    function stake(uint256 _amount, address _to) external nonReentrant {
        require(!isShutdown, 'shutdown');

        //dont need to call checkpoint since _mint() will

        if (_amount > 0) {
            _mint(_to, _amount);
            IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);
            IRewardStaking(convexPool).stake(_amount);
        }

        emit Deposited(msg.sender, _to, _amount, false);
    }

    //withdraw to convex deposit token
    function withdraw(uint256 _amount) external nonReentrant {
        //dont need to call checkpoint since _burn() will

        if (_amount > 0) {
            _burn(msg.sender, _amount);
            IRewardStaking(convexPool).withdraw(_amount, false);
            IERC20(convexToken).safeTransfer(msg.sender, _amount);
        }

        emit Withdrawn(msg.sender, _amount, false);
    }

    //withdraw to underlying curve lp token
    function withdrawAndUnwrap(uint256 _amount) external nonReentrant {
        //dont need to call checkpoint since _burn() will

        if (_amount > 0) {
            _burn(msg.sender, _amount);
            IRewardStaking(convexPool).withdrawAndUnwrap(_amount, false);
            IERC20(curveToken).safeTransfer(msg.sender, _amount);
        }

        //events
        emit Withdrawn(msg.sender, _amount, true);
    }
}
