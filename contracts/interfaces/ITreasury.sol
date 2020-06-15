pragma solidity ^0.6.2;


interface ITreasury {
    function debt() external view returns(uint256);
    function savings() external returns(uint256);
    function pushDai() external;
    function pullDai(address user, uint256 dai) external;
    function pushChai() external;
    function pullChai(address user, uint256 chai) external;
    function pushWeth() external;
    function pullWeth(address to, uint256 weth) external;
    function fork(address to, uint256 weth, uint256 dai) external;
    function shutdown() external;
}