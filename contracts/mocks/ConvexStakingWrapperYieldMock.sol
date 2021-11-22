// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
contract ConvexStakingWrapperYieldMock is ERC20{
    
    constructor() 
        ERC20(
            "StakedConvexToken",
            "stkCvx"
        ){
            _mint(msg.sender, 1000*10e18);
    }
    function deposit(uint256 _amount, address _to) external {

        if (_amount > 0) {
            _mint(_to, _amount);
            // IERC20(curveToken).safeTransferFrom(msg.sender, address(this), _amount);
            
        }
    }

    function stake(uint256 _amount, address _to) external {
        if (_amount > 0) {
            _mint(_to, _amount);
            // IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);   
        }
    }

    function withdraw(uint256 _amount) external {
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            // IRewardStaking(convexPool).withdraw(_amount, false);
            // IERC20(convexToken).safeTransfer(msg.sender, _amount);
        }
    }

    function withdrawAndUnwrap(uint256 _amount) external {
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            // IRewardStaking(convexPool).withdrawAndUnwrap(_amount, false);
            // IERC20(curveToken).safeTransfer(msg.sender, _amount);
        }
    }
}