pragma solidity ^0.6.2;


interface ITreasury {
    function push() external;
    function pull(address user, uint256 dai) external;
    function post() external;
    function withdraw(address to, uint256 weth) external;
}