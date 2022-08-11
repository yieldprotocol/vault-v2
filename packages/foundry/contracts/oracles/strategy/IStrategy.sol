// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

interface IStrategy {
    
    // function base() external returns(IERC20);
    
    // function fyToken() external returns(IFYToken);
    
    function cached() external view returns (uint256);

    function totalSupply() external view returns (uint256);
}