pragma solidity ^0.6.10;

import "./IYDai.sol";


interface IDealer {
    function series(uint256) external returns (IYDai);
    function systemPosted(bytes32) external returns (uint256);
    function systemDebtYDai(bytes32, uint256) external returns (uint256);
    function posted(bytes32, address) external view returns (uint256);
    function debtYDai(bytes32, uint256, address) external returns (uint256);
    function totalDebtDai(bytes32, address) external returns (uint256);
    function isCollateralized(bytes32, address) external returns (bool);
    function grab(bytes32, address, uint256, uint256) external;
    function shutdown() external;
    function post(bytes32, address, address, uint256) external;
    function withdraw(bytes32, address, address, uint256) external;
    function borrow(bytes32, uint256, address, address, uint256) external;
    function repayYDai(bytes32, uint256, address, address, uint256) external;
    function repayDai(bytes32, uint256, address, address, uint256) external;
}