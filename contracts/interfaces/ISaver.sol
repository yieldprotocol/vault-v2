pragma solidity ^0.6.2;


interface ISaver {
    function join(uint256 chai) external;
    function join(address user, uint256 chai) external;
    function exit(uint256 chai) external;
    function exit(address user, uint256 chai) external;
}
