pragma solidity ^0.6.2;


interface ISaver {
    function savings() external view returns(uint256);
    function join(address user, uint256 chai) external;
    function exit(address user, uint256 chai) external;
}