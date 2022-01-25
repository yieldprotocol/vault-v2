// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@yield-protocol/utils-v2/contracts/token/ERC20.sol';
import '@yield-protocol/vault-interfaces/DataTypes.sol';
import '@yield-protocol/utils-v2/contracts/token/TransferHelper.sol';

contract ConvexPoolMock {
    using TransferHelper for IERC20;
    IERC20 rewardToken;
    IERC20 stakingToken;
    IERC20 cvx;
    uint256 _totalSupply;
    mapping(address => uint256) _balances;

    constructor(
        IERC20 _rewardToken,
        IERC20 _stakingToken,
        IERC20 cvx_
    ) {
        rewardToken = _rewardToken;
        stakingToken = _stakingToken;
        cvx = cvx_;
    }

    /// @notice Simulates getting reward tokens
    /// @param _account The account for which to getreward for
    /// @param _claimExtras Whether to claim the extra rewards
    /// @return true if reward was sent
    function getReward(address _account, bool _claimExtras) public returns (bool) {
        rewardToken.transfer(_account, 1e18); //Fixed reward transfer
        cvx.transfer(_account, 1e18);
        return true;
    }

    /// @notice Stakes the token of a user
    /// @param _amount The amount of token to be staked
    /// @return true if the staking was successful
    function stake(uint256 _amount) public returns (bool) {
        require(_amount > 0, 'RewardPool : Cannot stake 0');

        _totalSupply = _totalSupply + _amount;
        _balances[msg.sender] = _balances[msg.sender] + _amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        return true;
    }

    /// @notice Withdraws the staking token deposited by the user
    /// @param _amount The amount of staking token to withdraw
    /// @param _claim Whether to claim the extra rewards
    /// @return true if the withdrawal was successful
    function withdraw(uint256 _amount, bool _claim) public returns (bool) {
        require(_amount > 0, 'RewardPool : Cannot withdraw 0');

        _totalSupply = _totalSupply - _amount;
        _balances[msg.sender] = _balances[msg.sender] - _amount;

        stakingToken.safeTransfer(msg.sender, _amount);

        return true;
    }
}
