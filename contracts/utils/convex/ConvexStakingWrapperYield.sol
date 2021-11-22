//https://etherscan.io/address/0x3ba207c25a278524e1cc7faaea950753049072a4#code
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
pragma experimental ABIEncoderV2;

import './ConvexStakingWrapper.sol';
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

//Staking wrapper for Yield platform
//use convex LP positions as collateral while still receiving rewards
contract ConvexStakingWrapperYield is ConvexStakingWrapper,AccessControl {
    using SafeERC20 for IERC20;
    using Address for address;

    constructor() public {}

    function initialize(
        address _curveToken,
        address _convexToken,
        address _convexPool,
        uint256 _poolId,
        address _vault
    ) external override auth{
        require(!isInit, 'already init');
        owner = address(0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB); //default to convex multisig
        emit OwnershipTransferred(address(0), owner);
        _tokenname = string(abi.encodePacked('Staked ', ERC20(_convexToken).name(), ' Yield'));
        _tokensymbol = string(abi.encodePacked('stk', ERC20(_convexToken).symbol(), '-yield'));
        isShutdown = false;
        isInit = true;
        curveToken = _curveToken;
        convexToken = _convexToken;
        convexPool = _convexPool;
        convexPoolId = _poolId;
        collateralVault = address(_vault); //TODO: set to the join so that the protocol can't claim the reward

        //add rewards
        addRewards();
        setApprovals();
    }
}
