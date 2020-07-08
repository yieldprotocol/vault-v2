pragma solidity ^0.6.10;


interface IMarket {
    function sellChai(address to, uint128 chaiIn) external;
    function buyChai(address to, uint128 chaiOut) external;
    function sellYDai(address to, uint128 yDaiIn) external;
    function buyYDai(address to, uint128 yDaiOut) external;
}