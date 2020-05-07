pragma solidity ^0.6.2;


interface ILender {
    function post(uint256 weth) external;
    function post(address from, uint256 weth) external;
    function withdraw(uint256 weth) external;
    function withdraw(address to, uint256 weth) external;
    function repay(uint256 dai) external;
    function repay(address from, uint256 dai) external;
    function borrow(uint256 dai) external;
    function borrow(address to, uint256 dai) external;
}
