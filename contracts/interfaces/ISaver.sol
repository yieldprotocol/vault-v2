pragma solidity ^0.6.2;


interface ISaver {
    function savings() external returns(uint256);
    function hold(address user, uint256 dai) external;
    function release(address user, uint256 dai) external;
    function releaseChai(address user, uint256 chai) external;
}