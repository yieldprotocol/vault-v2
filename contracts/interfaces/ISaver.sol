pragma solidity ^0.6.2;


interface ISaver {
    function savings() external returns(uint256);
    function join(address user, uint256 dai) external;
    function exit(address user, uint256 dai) external;
}