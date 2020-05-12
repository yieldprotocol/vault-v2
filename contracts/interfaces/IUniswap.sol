pragma solidity ^0.6.2;


/// @dev Interface to interact with the Uniswap V2 Pair contract
/// Contract at: https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2Pair.sol
interface IUniswap {
    function getReserves() external view returns (uint112, uint112, uint32);
    function totalSupply() external view returns (uint256);
}