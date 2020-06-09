pragma solidity ^0.6.2;


/// @dev interface for the End contract from MakerDAO
interface IEnd {
    function tag(bytes32) external returns(uint256);
    function skim(bytes32, address) external;
}