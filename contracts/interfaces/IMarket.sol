pragma solidity ^0.6.10;


interface IMarket {
    function sellDai(address from, address to, uint128 daiIn) external returns(uint128);
    function buyDai(address from, address to, uint128 daiOut) external returns(uint128);
    function sellYDai(address from, address to, uint128 yDaiIn) external returns(uint128);
    function buyYDai(address from, address to, uint128 yDaiOut) external returns(uint128);
}