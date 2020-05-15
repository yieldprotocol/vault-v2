pragma solidity ^0.6.2;


interface ILender {
    function debt() external view returns(uint256);
    function power() external view returns(uint256);
    function post(address from, uint256 weth) external;
    function withdraw(address to, uint256 weth) external;
    function repay(address from, uint256 dai) external;
    function borrow(address to, uint256 dai) external;
}
