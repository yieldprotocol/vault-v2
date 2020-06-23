pragma solidity ^0.6.2;

import "./IYDai.sol";


interface IDealer {
    function series(uint256) external returns (IYDai);
    function systemDebt() external returns (uint256);
    function posted(bytes32, address) external view returns (uint256);
    function totalDebtDai(bytes32, address) external returns (uint256);
    function totalDebtYDai(bytes32, address) external view returns (uint256);
    function isCollateralized(bytes32, address) external returns (bool);
    function erase(bytes32, address) external returns (uint256, uint256);
    function grab(bytes32, address, uint256, uint256) external;
    function shutdown() external;
    function post(bytes32, address, address, uint256) external;
    function withdraw(bytes32, address, address, uint256) external;
}