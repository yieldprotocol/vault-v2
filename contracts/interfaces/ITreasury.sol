pragma solidity ^0.6.2;


interface ITreasury {
    function push(address user, uint256 dai) external;
    function pull(address user, uint256 dai) external;
    function post(address from, uint256 weth) external;
    function withdraw(address to, uint256 weth) external;
    function releaseChai(address user, uint256 chai) external;
}