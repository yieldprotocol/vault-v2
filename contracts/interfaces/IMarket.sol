pragma solidity ^0.6.10;


interface IMarket {
    function sellChai(address from, address to, uint128 chaiIn) external;
    function buyChai(address from, address to, uint128 chaiOut) external;
    function sellYDai(address from, address to, uint128 yDaiIn) external;
    function buyYDai(address from, address to, uint128 yDaiOut) external;
}