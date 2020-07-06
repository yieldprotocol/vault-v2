pragma solidity ^0.6.10;


interface IMarket {
    function sellChai(uint128 chaiIn) external;
    function buyChai(uint128 chaiOut) external;
    function sellYDai(uint128 yDaiIn) external;
    function buyYDai(uint128 yDaiOut) external;
}