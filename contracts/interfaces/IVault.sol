pragma solidity ^0.6.2;

import "./IYDai.sol";

interface IVault {
    function series(uint256) external returns (IYDai);
    function systemDebt() external view returns (uint256);
    function posted(bytes32, address) external view returns (uint256);
    function totalDebtYDai(bytes32, address) external view returns (uint256);
    function erase(bytes32, address) external returns (uint256, uint256);
    function shutdown() external;
}