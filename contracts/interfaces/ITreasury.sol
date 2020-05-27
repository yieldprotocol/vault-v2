pragma solidity ^0.6.2;


interface ITreasury {
    function pushDai() external;
    function pullDai(address user, uint256 dai) external;
    function pushChai() external;
    function pullChai(address user, uint256 chai) external;
    function pushWeth() external;
    function pullWeth(address to, uint256 weth) external;
}